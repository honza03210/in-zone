import Foundation

/// Messages exchanged with anchors over the BLE transport characteristic,
/// kept as pure functions so the protocol logic is unit-testable.
enum NIMessage: Equatable {
    case accessoryConfig(Data)
    case uwbDidStart
    case uwbDidStop
    case unknown(msgId: UInt8)

    static func parse(_ data: Data) -> NIMessage? {
        guard let msgId = data.first else { return nil }
        let payload = Data(data.dropFirst())

        switch msgId {
        case BLE.msgAccessoryConfig: return .accessoryConfig(payload)
        case BLE.msgUwbDidStart:     return .uwbDidStart
        case BLE.msgUwbDidStop:      return .uwbDidStop
        default:                     return .unknown(msgId: msgId)
        }
    }

    static func encodeInitialize() -> Data {
        Data([BLE.msgInitialize])
    }

    static func encodeConfigure(shareableConfig: Data) -> Data {
        var msg = Data([BLE.msgConfigure])
        msg.append(shareableConfig)
        return msg
    }

    static func encodeStop() -> Data {
        Data([BLE.msgStop])
    }
}

extension BLE {
    /// Anchor labels come from UICR flash, padded with 0xFF (erased) or 0x00.
    static func decodeLabel(_ data: Data) -> String {
        let cleaned = data.filter { $0 != 0xFF && $0 != 0x00 }
        return String(data: cleaned, encoding: .utf8) ?? ""
    }
}
