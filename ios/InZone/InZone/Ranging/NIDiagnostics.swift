import Foundation
import NearbyInteraction

/// Surfaces Nearby Interaction availability and the last session error so the
/// UI can show *why* ranging isn't working. The most important case for a
/// sideloaded / free-provisioned build: the device has the UWB hardware
/// (`supported == true`) but the `com.apple.developer.nearby-interaction.accessory`
/// entitlement isn't granted, so starting an accessory session fails at
/// runtime — that failure shows up here as `lastError`.
final class NIDiagnostics: ObservableObject {
    static let shared = NIDiagnostics()

    /// Does this device's hardware support Nearby Interaction at all?
    @Published private(set) var supported: Bool
    /// Last error from creating/running an NI accessory session (nil = none yet).
    @Published private(set) var lastError: String?
    @Published private(set) var lastErrorAt: Date?
    /// Set true once any NI session has produced a distance — proves NI works.
    @Published private(set) var everRanged = false

    // Handshake step counters, to pinpoint where ranging stalls on-device:
    // initialize sent -> accessory config received from anchor -> NI session
    // started -> shareable config generated -> configure sent to anchor.
    @Published private(set) var initSent = 0
    @Published private(set) var cfgReceived = 0
    @Published private(set) var sessionStarted = 0
    @Published private(set) var shareableGenerated = 0
    @Published private(set) var configureSent = 0

    func noteInitSent()    { DispatchQueue.main.async { self.initSent += 1 } }
    func noteCfgReceived() { DispatchQueue.main.async { self.cfgReceived += 1 } }
    func noteSessionStarted()    { DispatchQueue.main.async { self.sessionStarted += 1 } }
    func noteShareable()   { DispatchQueue.main.async { self.shareableGenerated += 1 } }
    func noteConfigureSent() { DispatchQueue.main.async { self.configureSent += 1 } }

    private init() {
        // isSupported reports the hardware capability (U1/U2 chip present).
        supported = NISession.isSupported
    }

    func report(_ message: String) {
        DispatchQueue.main.async {
            self.lastError = message
            self.lastErrorAt = Date()
        }
    }

    func markRanged() {
        DispatchQueue.main.async {
            if !self.everRanged { self.everRanged = true }
            self.lastError = nil
        }
    }

    /// True when there's something the user should be told about.
    var isProblem: Bool { !supported || (lastError != nil && !everRanged) }

    var statusText: String {
        if !supported {
            return "NearbyInteraction is NOT accessible: this device's hardware doesn't support it (or the app lacks the capability)."
        }
        if let e = lastError, !everRanged {
            return "NearbyInteraction not accessible — session error: \(e). "
                + "On a free-account/sideloaded build this usually means the "
                + "nearby-interaction accessory entitlement isn't granted."
        }
        if everRanged {
            return "NearbyInteraction OK (ranging has worked)."
        }
        return "NearbyInteraction supported; no session started yet."
    }
}
