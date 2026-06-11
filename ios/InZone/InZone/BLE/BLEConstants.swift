import CoreBluetooth

enum BLE {
    static let transportService = CBUUID(string: "49A70001-9A91-4B5C-8E3F-2D1C7A6B5E40")
    static let rxChar           = CBUUID(string: "49A70002-9A91-4B5C-8E3F-2D1C7A6B5E40")
    static let txChar           = CBUUID(string: "49A70003-9A91-4B5C-8E3F-2D1C7A6B5E40")

    static let infoService      = CBUUID(string: "49A70010-9A91-4B5C-8E3F-2D1C7A6B5E40")
    static let anchorIdChar     = CBUUID(string: "49A70011-9A91-4B5C-8E3F-2D1C7A6B5E40")
    static let labelChar        = CBUUID(string: "49A70012-9A91-4B5C-8E3F-2D1C7A6B5E40")
    static let fwVersionChar    = CBUUID(string: "49A70013-9A91-4B5C-8E3F-2D1C7A6B5E40")
    static let modeChar         = CBUUID(string: "49A70014-9A91-4B5C-8E3F-2D1C7A6B5E40")
    static let identifyChar     = CBUUID(string: "49A70015-9A91-4B5C-8E3F-2D1C7A6B5E40")

    static let msgInitialize:      UInt8 = 0x0A
    static let msgConfigure:       UInt8 = 0x0B
    static let msgStop:            UInt8 = 0x0C

    static let msgAccessoryConfig: UInt8 = 0x01
    static let msgUwbDidStart:     UInt8 = 0x02
    static let msgUwbDidStop:      UInt8 = 0x03
}
