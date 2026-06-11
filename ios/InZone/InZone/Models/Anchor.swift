import Foundation

enum AnchorState: String, CaseIterable {
    case discovered, connecting, connected, ranging

    var sortOrder: Int {
        switch self {
        case .ranging:      return 0
        case .connected:    return 1
        case .connecting:   return 2
        case .discovered:   return 3
        }
    }
}

struct Anchor: Identifiable {
    let id: UUID
    var anchorId: UInt8 = 0xFF
    var label: String = ""
    var firmwareVersion: String = ""
    var mode: UInt8 = 0
    var peripheralName: String = ""
    var rssi: Int = -100
    var state: AnchorState = .discovered
    var distance: Float?
    var direction: SIMD3<Float>?
    var lastUpdate: Date?

    var displayName: String {
        if !label.isEmpty { return label }
        if anchorId != 0xFF { return "Anchor \(anchorId)" }
        return peripheralName.isEmpty ? "Unknown" : peripheralName
    }

    var isConnected: Bool {
        state == .connected || state == .ranging
    }
}
