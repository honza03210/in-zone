import Foundation
import os

/// Drives Nearby Interaction ranging across all connected anchors.
///
/// Each anchor gets its own NISession, and they all run **concurrently** and
/// stay running — iOS time-multiplexes the UWB channel across the sessions
/// itself. (An earlier round-robin design that started one session, ranged
/// for ~400 ms, then stopped it and moved on did not work with the stock
/// Qorvo QANI firmware: a session needs to stay up to keep ranging, so only
/// the currently-active anchor ever updated.)
class RangingScheduler: ObservableObject {
    @Published var isRunning = false
    @Published var currentDistances: [UInt8: Float] = [:]
    @Published var currentDirections: [UInt8: SIMD3<Float>] = [:]
    @Published var sweepCount: Int = 0   // total range updates received (debug)

    /// Restart an anchor's session if it produces no range update for this long.
    /// Concurrent QANI sessions tend to drift/stall over time without firing an
    /// NISession invalidation; re-handshaking the stalled one recovers it (this
    /// is what a manual Stop→Start does, automated per-anchor).
    var stallTimeout: TimeInterval = 3.0

    private var activeSessions: [UUID: NISessionManager] = [:]
    private var starting: Set<UUID> = []         // initialize sent, session not yet up
    private var connectedAnchors: Set<UUID> = []
    private var filters: [UInt8: DistanceFilter] = [:]
    private var lastRange: [UUID: Date] = [:]    // last activity per anchor (for stall watchdog)
    private var watchdog: Timer?
    private weak var bleManager: BLEManager?
    private let log = Logger(subsystem: "com.inzone", category: "Scheduler")

    func start(anchors: [UUID], bleManager: BLEManager) {
        guard !isRunning else { return }
        self.bleManager = bleManager
        connectedAnchors = Set(anchors)
        isRunning = true
        filters.removeAll()

        setupCallbacks(bleManager)
        // Bring up a concurrent ranging session with every connected anchor.
        for id in anchors {
            startAnchor(id)
        }

        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.checkStalls()
        }
        log.info("Ranging started with \(anchors.count) anchors (concurrent)")
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false

        watchdog?.invalidate()
        watchdog = nil
        for (id, session) in activeSessions {
            session.stop()
            bleManager?.sendStop(to: id)
        }
        activeSessions.removeAll()
        starting.removeAll()
        connectedAnchors.removeAll()
        lastRange.removeAll()
        teardownCallbacks()
        log.info("Ranging stopped")
    }

    // MARK: - Internal

    private func setupCallbacks(_ ble: BLEManager) {
        ble.onAccessoryConfig = { [weak self] id, data in
            self?.handleAccessoryConfig(from: id, data: data)
        }
        ble.onUwbDidStart = { [weak self] id in
            self?.log.info("UWB ranging active on \(id)")
        }
        ble.onUwbDidStop = { _ in }
        ble.onDisconnect = { [weak self] id in
            self?.handleDisconnect(id)
        }
    }

    private func teardownCallbacks() {
        bleManager?.onAccessoryConfig = nil
        bleManager?.onUwbDidStart = nil
        bleManager?.onUwbDidStop = nil
        bleManager?.onDisconnect = nil
    }

    /// Kick off the NI handshake with one anchor (idempotent).
    private func startAnchor(_ id: UUID) {
        guard connectedAnchors.contains(id),
              activeSessions[id] == nil,
              !starting.contains(id) else { return }
        starting.insert(id)
        lastRange[id] = Date() // grace period for the handshake to complete
        log.info("Initiating NI handshake with \(id)")
        bleManager?.sendInitialize(to: id)
    }

    /// Restart any anchor that hasn't produced a range update within stallTimeout.
    private func checkStalls() {
        guard isRunning else { return }
        let now = Date()
        for id in connectedAnchors {
            let last = lastRange[id] ?? now
            if now.timeIntervalSince(last) > stallTimeout {
                log.info("Anchor \(id) stalled — restarting session")
                restartAnchor(id)
            }
        }
    }

    private func restartAnchor(_ id: UUID) {
        activeSessions[id]?.stop()
        activeSessions[id] = nil
        starting.remove(id)
        bleManager?.sendStop(to: id)
        lastRange[id] = Date() // grace while it re-handshakes
        // Let the accessory tear its session down before re-initializing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, self.isRunning else { return }
            self.startAnchor(id)
        }
    }

    private func handleAccessoryConfig(from anchorId: UUID, data: Data) {
        starting.remove(anchorId)

        let session = NISessionManager(anchorPeripheralId: anchorId)
        activeSessions[anchorId] = session

        session.onShareableConfig = { [weak self] shareableData in
            self?.bleManager?.sendConfigure(to: anchorId, shareableConfig: shareableData)
        }
        session.onRangeUpdate = { [weak self] distance, direction in
            self?.handleRange(anchorId: anchorId, distance: distance, direction: direction)
        }
        session.onSessionInvalidated = { [weak self] in
            self?.handleSessionEnded(anchorId)
        }

        session.start(accessoryConfigData: data)
    }

    private func handleRange(anchorId: UUID, distance: Float, direction: SIMD3<Float>?) {
        lastRange[anchorId] = Date()

        guard let ble = bleManager,
              let anchor = ble.anchors[anchorId],
              anchor.anchorId != 0xFF else { return }
        let aid = anchor.anchorId

        var filter = filters[aid] ?? DistanceFilter()
        let filtered = filter.update(distance, at: Date())
        filters[aid] = filter

        currentDistances[aid] = filtered
        if let dir = direction {
            currentDirections[aid] = dir
        }
        sweepCount += 1

        ble.anchors[anchorId]?.distance = filtered
        ble.anchors[anchorId]?.direction = direction
        ble.anchors[anchorId]?.lastUpdate = Date()
    }

    /// A session ended (invalidated). Retry it shortly if the anchor is still
    /// connected and we're still ranging.
    private func handleSessionEnded(_ anchorId: UUID) {
        activeSessions[anchorId] = nil
        starting.remove(anchorId)
        bleManager?.sendStop(to: anchorId)

        guard isRunning, connectedAnchors.contains(anchorId) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self, self.isRunning else { return }
            self.startAnchor(anchorId)
        }
    }

    private func handleDisconnect(_ anchorId: UUID) {
        connectedAnchors.remove(anchorId)
        activeSessions[anchorId]?.stop()
        activeSessions[anchorId] = nil
        starting.remove(anchorId)

        // Drop only this anchor's distance, not everyone's.
        if let aid = bleManager?.anchors[anchorId]?.anchorId {
            currentDistances[aid] = nil
            currentDirections[aid] = nil
        }

        if connectedAnchors.isEmpty {
            stop()
        }
    }
}
