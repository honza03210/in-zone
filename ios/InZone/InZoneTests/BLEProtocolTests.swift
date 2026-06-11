import XCTest
@testable import InZone

final class BLEProtocolTests: XCTestCase {

    // MARK: - Message ID constants

    func testPhoneToAnchorMessageIDs() {
        XCTAssertEqual(BLE.msgInitialize, 0x0A)
        XCTAssertEqual(BLE.msgConfigure,  0x0B)
        XCTAssertEqual(BLE.msgStop,       0x0C)
    }

    func testAnchorToPhoneMessageIDs() {
        XCTAssertEqual(BLE.msgAccessoryConfig, 0x01)
        XCTAssertEqual(BLE.msgUwbDidStart,     0x02)
        XCTAssertEqual(BLE.msgUwbDidStop,      0x03)
    }

    // MARK: - Message encoding

    func testInitializeMessage() {
        let msg = Data([BLE.msgInitialize])
        XCTAssertEqual(msg.count, 1)
        XCTAssertEqual(msg[0], 0x0A)
    }

    func testConfigureMessage() {
        let shareableConfig = Data([0xDE, 0xAD, 0xBE, 0xEF])
        var msg = Data([BLE.msgConfigure])
        msg.append(shareableConfig)

        XCTAssertEqual(msg.count, 5)
        XCTAssertEqual(msg[0], 0x0B)
        XCTAssertEqual(Data(msg.dropFirst()), shareableConfig)
    }

    func testStopMessage() {
        let msg = Data([BLE.msgStop])
        XCTAssertEqual(msg.count, 1)
        XCTAssertEqual(msg[0], 0x0C)
    }

    // MARK: - Message parsing

    func testParseAccessoryConfig() {
        let configPayload = Data(repeating: 0x42, count: 64)
        var msg = Data([BLE.msgAccessoryConfig])
        msg.append(configPayload)

        let msgId = msg[0]
        let payload = Data(msg.dropFirst())

        XCTAssertEqual(msgId, 0x01)
        XCTAssertEqual(payload.count, 64)
        XCTAssertEqual(payload, configPayload)
    }

    func testParseUwbDidStart() {
        let msg = Data([BLE.msgUwbDidStart])
        XCTAssertEqual(msg[0], 0x02)
        XCTAssertEqual(msg.count, 1)
    }

    func testParseUwbDidStop() {
        let msg = Data([BLE.msgUwbDidStop])
        XCTAssertEqual(msg[0], 0x03)
        XCTAssertEqual(msg.count, 1)
    }

    // MARK: - UUID format

    func testServiceUUIDs() {
        XCTAssertEqual(BLE.transportService.uuidString, "49A70001-9A91-4B5C-8E3F-2D1C7A6B5E40")
        XCTAssertEqual(BLE.infoService.uuidString,      "49A70010-9A91-4B5C-8E3F-2D1C7A6B5E40")
    }

    func testTransportCharacteristicUUIDs() {
        XCTAssertEqual(BLE.rxChar.uuidString, "49A70002-9A91-4B5C-8E3F-2D1C7A6B5E40")
        XCTAssertEqual(BLE.txChar.uuidString, "49A70003-9A91-4B5C-8E3F-2D1C7A6B5E40")
    }

    func testInfoCharacteristicUUIDs() {
        XCTAssertEqual(BLE.anchorIdChar.uuidString,  "49A70011-9A91-4B5C-8E3F-2D1C7A6B5E40")
        XCTAssertEqual(BLE.labelChar.uuidString,     "49A70012-9A91-4B5C-8E3F-2D1C7A6B5E40")
        XCTAssertEqual(BLE.fwVersionChar.uuidString, "49A70013-9A91-4B5C-8E3F-2D1C7A6B5E40")
        XCTAssertEqual(BLE.modeChar.uuidString,      "49A70014-9A91-4B5C-8E3F-2D1C7A6B5E40")
        XCTAssertEqual(BLE.identifyChar.uuidString,  "49A70015-9A91-4B5C-8E3F-2D1C7A6B5E40")
    }

    // MARK: - Identify payload

    func testIdentifyPayloadDefaultDuration() {
        let payload = Data([5])
        XCTAssertEqual(payload.count, 1)
        XCTAssertEqual(payload[0], 5)
    }

    func testIdentifyPayloadCustomDuration() {
        let seconds: UInt8 = 10
        let payload = Data([seconds])
        XCTAssertEqual(payload[0], 10)
    }
}
