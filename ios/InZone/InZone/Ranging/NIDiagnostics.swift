import Foundation
import NearbyInteraction

/// Surfaces Nearby Interaction availability, the handshake progress, and the
/// last session error so the UI can show *why* ranging isn't working.
/// (Nearby Interaction needs no entitlement — it's gated by the usage-string
/// permission only — so a stall here is a runtime/protocol issue, not signing.)
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
    /// Byte length of the most recent accessory-configuration blob handed to
    /// NINearbyAccessoryConfiguration. A tiny value (≈19) means the BLE
    /// notification was truncated; a sane Qorvo config is ~30+ bytes.
    @Published private(set) var lastConfigLen = 0
    /// Set when run() succeeded but NI produced no shareable config within the
    /// watchdog window and reported no error — i.e. a silent NI stall.
    @Published private(set) var stalled = false

    func noteInitSent()    { DispatchQueue.main.async { self.initSent += 1 } }
    func noteCfgReceived() { DispatchQueue.main.async { self.cfgReceived += 1 } }
    func noteSessionStarted()    { DispatchQueue.main.async { self.sessionStarted += 1 } }
    func noteShareable()   { DispatchQueue.main.async { self.shareableGenerated += 1; self.stalled = false } }
    func noteConfigureSent() { DispatchQueue.main.async { self.configureSent += 1 } }
    func noteConfigLen(_ n: Int) { DispatchQueue.main.async { self.lastConfigLen = n } }
    func noteStall()       { DispatchQueue.main.async { self.stalled = true } }

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
    var isProblem: Bool { !supported || stalled || (lastError != nil && !everRanged) }

    var statusText: String {
        if !supported {
            return "NearbyInteraction is NOT accessible: this device's hardware doesn't support it."
        }
        if let e = lastError, !everRanged {
            return "NearbyInteraction session error: \(e)"
        }
        if stalled {
            return "NI accepted the session but never produced a shareable config "
                + "and reported no error (accessory cfg = \(lastConfigLen) bytes). "
                + "Likely a malformed/truncated accessory config from the anchor."
        }
        if everRanged {
            return "NearbyInteraction OK (ranging has worked)."
        }
        return "NearbyInteraction supported; no session started yet."
    }
}
