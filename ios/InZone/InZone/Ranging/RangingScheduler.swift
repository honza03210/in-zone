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

    /// Restart an anchor's session if it produces no range update for this long
    /// (catches a hard stall).
    var stallTimeout: TimeInterval = 3.0
    /// Proactively re-handshake each session at this age, before it decays.
    /// Concurrent QANI sessions slow down over time (UWB airtime/sync drift)
    /// without firing an NISession invalidation; a fresh handshake recovers the
    /// rate — exactly what a manual Stop→Start does. Refreshes are staggered per
    /// anchor so they don't all gap at once.
    var refreshInterval: TimeInterval = 20.0

    private var activeSessions: [UUID: NISessionManager] = [:]
    private var starting: Set<UUID> = []         // initialize sent, session not yet up
    private var connectedAnchors: Set<UUID> = []
    private var filters: [UInt8: DistanceFilter] = [:]
    private var lastRange: [UUID: Date] = [:]    // last range update per anchor
    private var lastStart: [UUID: Date] = [:]    // last (re)handshake time per anchor
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
        // Bring up a session with every connected anchor, staggered ~0.3s apart
        // so four handshakes don't contend on the radio simultaneously.
        for (i, id) in anchors.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.3) { [weak self] in
                guard let self, self.isRunning else { return }
                self.startAnchor(id)
            }
        }

        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.maintainSessions()
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
        lastStart.removeAll()
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
        let now = Date()
        lastRange[id] = now // grace period for the handshake to complete
        lastStart[id] = now
        log.info("Initiating NI handshake with \(id)")
        bleManager?.sendInitialize(to: id)
    }

    /// Once a second: restart any stalled anchor, and proactively refresh any
    /// session that has been running long enough to start decaying.
    private func maintainSessions() {
        guard isRunning else { return }
        let now = Date()
        for id in connectedAnchors {
            let idle = now.timeIntervalSince(lastRange[id] ?? now)
            if idle > stallTimeout {
                log.info("Anchor \(id) stalled — restarting session")
                restartAnchor(id)
                continue
            }
            // Proactive refresh: only for established (not mid-handshake)
            // sessions, staggered per anchor so they don't all gap together.
            if !starting.contains(id), activeSessions[id] != nil {
                let age = now.timeIntervalSince(lastStart[id] ?? now)
                if age > refreshAge(for: id) {
                    log.info("Anchor \(id) refresh (age \(Int(age))s)")
                    restartAnchor(id)
                }
            }
        }
    }

    /// Stagger refresh ages across anchors (e.g. 20, 25, 30, 35s) so only one
    /// anchor re-handshakes at a time.
    private func refreshAge(for id: UUID) -> TimeInterval {
        let idx = bleManager?.anchors[id]?.anchorId ?? 0
        return refreshInterval + Double(idx % 4) * (refreshInterval / 4)
    }

    private func restartAnchor(_ id: UUID) {
        activeSessions[id]?.stop()
        activeSessions[id] = nil
        starting.remove(id)
        bleManager?.sendStop(to: id)
        let now = Date()
        lastRange[id] = now // grace while it re-handshakes
        lastStart[id] = now // reset age so it isn't re-triggered during the gap
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
