import Foundation
import os

class RangingScheduler: ObservableObject {
    @Published var isRunning = false
    @Published var currentDistances: [UInt8: Float] = [:]
    @Published var currentDirections: [UInt8: SIMD3<Float>] = [:]
    @Published var sweepCount: Int = 0

    var dwellTime: TimeInterval = 0.4
    let maxConcurrent = 2

    private var activeSessions: [UUID: NISessionManager] = [:]
    private var dwellTimers: [UUID: Timer] = [:]
    private var anchorQueue: [UUID] = []
    private var connectedAnchors: Set<UUID> = []
    private var filters: [UInt8: DistanceFilter] = [:]
    private weak var bleManager: BLEManager?
    private let log = Logger(subsystem: "com.inzone", category: "Scheduler")

    func start(anchors: [UUID], bleManager: BLEManager) {
        guard !isRunning else { return }
        self.bleManager = bleManager
        connectedAnchors = Set(anchors)
        anchorQueue = anchors
        isRunning = true
        filters.removeAll()

        setupCallbacks(bleManager)
        fillSlots()
        log.info("Ranging started with \(anchors.count) anchors")
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false

        for (id, session) in activeSessions {
            session.stop()
            bleManager?.sendStop(to: id)
        }
        for (_, timer) in dwellTimers { timer.invalidate() }

        activeSessions.removeAll()
        dwellTimers.removeAll()
        anchorQueue.removeAll()
        teardownCallbacks()
        log.info("Ranging stopped")
    }

    // MARK: - Internal

    private func setupCallbacks(_ ble: BLEManager) {
        ble.onAccessoryConfig = { [weak self] id, data in
            self?.handleAccessoryConfig(from: id, data: data)
        }
        ble.onUwbDidStart = { [weak self] id in
            self?.handleUwbStarted(id)
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

    private func fillSlots() {
        while activeSessions.count < maxConcurrent, !anchorQueue.isEmpty {
            let id = anchorQueue.removeFirst()
            guard connectedAnchors.contains(id) else { continue }
            log.info("Initiating NI handshake with \(id)")
            bleManager?.sendInitialize(to: id)
        }
    }

    private func handleAccessoryConfig(from anchorId: UUID, data: Data) {
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

    private func handleUwbStarted(_ anchorId: UUID) {
        let timer = Timer.scheduledTimer(withTimeInterval: dwellTime, repeats: false) { [weak self] _ in
            self?.dwellComplete(anchorId)
        }
        dwellTimers[anchorId] = timer
    }

    private func handleRange(anchorId: UUID, distance: Float, direction: SIMD3<Float>?) {
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

        ble.anchors[anchorId]?.distance = filtered
        ble.anchors[anchorId]?.direction = direction
        ble.anchors[anchorId]?.lastUpdate = Date()
    }

    private func dwellComplete(_ anchorId: UUID) {
        guard isRunning else { return }

        activeSessions[anchorId]?.stop()
        activeSessions[anchorId] = nil
        dwellTimers[anchorId]?.invalidate()
        dwellTimers[anchorId] = nil
        bleManager?.sendStop(to: anchorId)

        if connectedAnchors.contains(anchorId) {
            anchorQueue.append(anchorId)
        }
        sweepCount += 1
        fillSlots()
    }

    private func handleSessionEnded(_ anchorId: UUID) {
        activeSessions[anchorId] = nil
        dwellTimers[anchorId]?.invalidate()
        dwellTimers[anchorId] = nil

        if isRunning, connectedAnchors.contains(anchorId) {
            anchorQueue.append(anchorId)
            fillSlots()
        }
    }

    private func handleDisconnect(_ anchorId: UUID) {
        connectedAnchors.remove(anchorId)
        activeSessions[anchorId]?.stop()
        activeSessions[anchorId] = nil
        dwellTimers[anchorId]?.invalidate()
        dwellTimers[anchorId] = nil
        anchorQueue.removeAll { $0 == anchorId }
        currentDistances.removeAll()

        if connectedAnchors.isEmpty {
            stop()
        }
    }
}
