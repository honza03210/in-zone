import Foundation
import os

class SimulatorService: ObservableObject {
    @Published var isActive = false
    @Published var isRanging = false
    @Published var phonePosition: CGPoint = .zero

    private var anchorUUIDs: [UInt8: UUID] = [:]
    private var timer: Timer?
    private weak var bleManager: BLEManager?
    private weak var scheduler: RangingScheduler?
    private weak var roomStore: RoomStore?
    private let log = Logger(subsystem: "com.inzone", category: "Simulator")

    static var isSimulatorEnvironment: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    private var layout: RoomLayout {
        roomStore?.layout ?? RoomLayout()
    }

    func activate(bleManager: BLEManager, scheduler: RangingScheduler, roomStore: RoomStore) {
        guard !isActive else { return }
        self.bleManager = bleManager
        self.scheduler = scheduler
        self.roomStore = roomStore

        phonePosition = CGPoint(
            x: CGFloat(roomStore.layout.width) / 2,
            y: CGFloat(roomStore.layout.height) / 2
        )

        for placement in roomStore.layout.anchors {
            let uuid = UUID()
            anchorUUIDs[placement.id] = uuid
            bleManager.anchors[uuid] = Anchor(
                id: uuid,
                anchorId: placement.id,
                label: placement.label,
                firmwareVersion: "sim",
                peripheralName: "InZone-A\(placement.id)",
                rssi: -40,
                state: .connected
            )
        }

        isActive = true
        log.info("Simulator activated with \(roomStore.layout.anchors.count) virtual anchors")
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

        // Layout may have shrunk since the phone was last dragged
        let px = min(max(Float(phonePosition.x), 0), layout.width)
        let py = min(max(Float(phonePosition.y), 0), layout.height)

        var dists: [UInt8: Float] = [:]
        for placement in layout.anchors {
            let dx = px - placement.x
            let dy = py - placement.y
            let trueDist = sqrt(dx * dx + dy * dy)
            let noise = Float.random(in: -0.03...0.03)
            dists[placement.id] = max(0.05, trueDist + noise)
        }
        scheduler.currentDistances = dists

        for placement in layout.anchors {
            guard let uuid = anchorUUIDs[placement.id] else { continue }
            bleManager.anchors[uuid]?.distance = dists[placement.id]
            bleManager.anchors[uuid]?.state = .ranging
            bleManager.anchors[uuid]?.lastUpdate = Date()
        }

        scheduler.sweepCount += 1
    }
}
