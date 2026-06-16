import Foundation
import NearbyInteraction
import os

class NISessionManager: NSObject {
    let anchorPeripheralId: UUID

    var onShareableConfig: ((Data) -> Void)?
    var onRangeUpdate: ((Float, SIMD3<Float>?) -> Void)?
    var onSessionInvalidated: (() -> Void)?

    private var session: NISession?
    private let log = Logger(subsystem: "com.inzone", category: "NI")

    init(anchorPeripheralId: UUID) {
        self.anchorPeripheralId = anchorPeripheralId
        super.init()
    }

    func start(accessoryConfigData: Data) {
        let s = NISession()
        s.delegate = self
        session = s

        do {
            let config = try NINearbyAccessoryConfiguration(
                accessoryData: accessoryConfigData,
                bluetoothPeerIdentifier: anchorPeripheralId
            )
            s.run(config)
            log.info("NI session running for \(self.anchorPeripheralId)")
        } catch {
            log.error("NI config failed: \(error)")
            NIDiagnostics.shared.report("config: \(error.localizedDescription)")
            session = nil
            onSessionInvalidated?()
        }
    }

    func stop() {
        session?.invalidate()
        session = nil
    }

    deinit {
        session?.invalidate()
    }
}

extension NISessionManager: NISessionDelegate {
    func session(_ session: NISession,
                 didGenerateShareableConfigurationData data: Data,
                 for object: NINearbyObject) {
        log.info("Shareable config ready (\(data.count) bytes)")
        onShareableConfig?(data)
    }

    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let obj = nearbyObjects.first else { return }
        if let d = obj.distance {
            NIDiagnostics.shared.markRanged()
            onRangeUpdate?(d, obj.direction)
        }
    }

    func session(_ session: NISession,
                 didRemove nearbyObjects: [NINearbyObject],
                 reason: NINearbyObject.RemovalReason) {
        log.info("NI object removed, reason=\(String(describing: reason))")
    }

    func session(_ session: NISession, didInvalidateWith error: Error) {
        log.error("NI session invalidated: \(error)")
        NIDiagnostics.shared.report("invalidated: \(error.localizedDescription)")
        self.session = nil
        onSessionInvalidated?()
    }

    func sessionWasSuspended(_ session: NISession) {
        log.info("NI session suspended (app backgrounded)")
    }

    func sessionSuspensionEnded(_ session: NISession) {
        log.info("NI session resumed")
    }
}
