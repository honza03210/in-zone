import Foundation
import NearbyInteraction
import os

class NISessionManager: NSObject {
    let anchorPeripheralId: UUID

    var onShareableConfig: ((Data) -> Void)?
    var onRangeUpdate: ((Float, SIMD3<Float>?) -> Void)?
    var onSessionInvalidated: (() -> Void)?

    private var session: NISession?
    private var generatedShareable = false
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
            // Use the basic accessory-data initializer (iOS 14+). This is the
            // one Qorvo's niq accessory-config targets — it mirrors Apple's
            // NINearbyAccessorySample. The iOS 16 accessoryData:
            // bluetoothPeerIdentifier: variant expects the newer extended /
            // capability TLVs; given a v1.0 Qorvo config it parses the header
            // (no throw) but silently emits no shareable config — the exact
            // stall we hit (sess=1, shr=0, no error).
            let config = try NINearbyAccessoryConfiguration(data: accessoryConfigData)
            s.run(config)
            NIDiagnostics.shared.noteSessionStarted()
            NIDiagnostics.shared.noteConfigLen(accessoryConfigData.count)
            log.info("NI session running for \(self.anchorPeripheralId), accessoryData=\(accessoryConfigData.count) bytes")

            // Watchdog: for an accessory session, NI normally calls back with the
            // shareable config within a fraction of a second. If nothing happens
            // (no callback, no invalidation error) we surface a "silent stall" so
            // the on-device debug panel shows it — there are no Console logs to
            // read on this setup.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self, self.session === s, !self.generatedShareable else { return }
                self.log.error("NI produced no shareable config 3s after run() and did not error")
                NIDiagnostics.shared.noteStall()
            }
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
        generatedShareable = true
        NIDiagnostics.shared.noteShareable()
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
