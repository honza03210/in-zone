import Foundation
import os

class SimulatorService: ObservableObject {
    @Published var isActive = false
    @Published var isRanging = false
    @Published var phonePosition: CGPoint = CGPoint(x: 2.5, y: 2.0)

    let roomSize = CGSize(width: 5.0, height: 4.0)

    struct AnchorPosition: Identifiable {
        let id: UInt8
        let x: CGFloat
        let y: CGFloat
        let label: String
    }

    static let anchorPositions: [AnchorPosition] = [
        AnchorPosition(id: 0, x: 0.0, y: 0.0, label: "door"),
        AnchorPosition(id: 1, x: 5.0, y: 0.0, label: "window"),
        AnchorPosition(id: 2, x: 5.0, y: 4.0, label: "desk"),
        AnchorPosition(id: 3, x: 0.0, y: 4.0, label: "bed"),
    ]

    private var anchorUUIDs: [UInt8: UUID] = [:]
    private var timer: Timer?
    private weak var bleManager: BLEManager?
    private weak var scheduler: RangingScheduler?
    private let log = Logger(subsystem: "com.inzone", category: "Simulator")

    static var isSimulatorEnvironment: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    func activate(bleManager: BLEManager, scheduler: RangingScheduler) {
        guard !isActive else { return }
        self.bleManager = bleManager
        self.scheduler = scheduler

        for ap in Self.anchorPositions {
            let uuid = UUID()
            anchorUUIDs[ap.id] = uuid
            bleManager.anchors[uuid] = Anchor(
                id: uuid,
                anchorId: ap.id,
                label: ap.label,
                firmwareVersion: "sim",
                peripheralName: "InZone-A\(ap.id)",
                rssi: -40,
                state: .connected
            )
        }

        isActive = true
        log.info("Simulator activated with 4 virtual anchors")
    }

    func startRanging() {
        guard isActive, !isRanging else { return }
        isRanging = true
        scheduler?.isRunning = true

        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.tick()
        }
        log.info("Simulated ranging started")
    }

    func stopRanging() {
        timer?.invalidate()
        timer = nil
        isRanging = false
        scheduler?.isRunning = false
        log.info("Simulated ranging stopped")
    }

    private func tick() {
        guard let scheduler = scheduler, let bleManager = bleManager else { return }

        let px = Float(phonePosition.x)
        let py = Float(phonePosition.y)

        var dists: [UInt8: Float] = [:]
        for ap in Self.anchorPositions {
            let dx = px - Float(ap.x)
            let dy = py - Float(ap.y)
            let trueDist = sqrt(dx * dx + dy * dy)
            let noise = Float.random(in: -0.03...0.03)
            dists[ap.id] = max(0.05, trueDist + noise)
        }
        scheduler.currentDistances = dists

        for ap in Self.anchorPositions {
            guard let uuid = anchorUUIDs[ap.id] else { continue }
            bleManager.anchors[uuid]?.distance = dists[ap.id]
            bleManager.anchors[uuid]?.state = .ranging
            bleManager.anchors[uuid]?.lastUpdate = Date()
        }

        scheduler.sweepCount += 1
    }
}
