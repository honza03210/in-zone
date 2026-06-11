import XCTest
@testable import InZone

final class BLEProtocolTests: XCTestCase {

    // MARK: - Encoding

    func testEncodeInitialize() {
        XCTAssertEqual(NIMessage.encodeInitialize(), Data([0x0A]))
    }

    func testEncodeConfigure() {
        let config = Data([0xDE, 0xAD, 0xBE, 0xEF])
        let msg = NIMessage.encodeConfigure(shareableConfig: config)
        XCTAssertEqual(msg, Data([0x0B, 0xDE, 0xAD, 0xBE, 0xEF]))
    }

    func testEncodeConfigureEmptyPayload() {
        XCTAssertEqual(NIMessage.encodeConfigure(shareableConfig: Data()), Data([0x0B]))
    }

    func testEncodeStop() {
        XCTAssertEqual(NIMessage.encodeStop(), Data([0x0C]))
    }

    // MARK: - Parsing

    func testParseAccessoryConfig() {
        let payload = Data(repeating: 0x42, count: 64)
        let msg = NIMessage.parse(Data([0x01]) + payload)
        XCTAssertEqual(msg, .accessoryConfig(payload))
    }

    func testParseAccessoryConfigEmptyPayload() {
        XCTAssertEqual(NIMessage.parse(Data([0x01])), .accessoryConfig(Data()))
    }

    func testParseUwbDidStart() {
        XCTAssertEqual(NIMessage.parse(Data([0x02])), .uwbDidStart)
    }

    func testParseUwbDidStop() {
        XCTAssertEqual(NIMessage.parse(Data([0x03])), .uwbDidStop)
    }

    func testParseUnknownMessageId() {
        XCTAssertEqual(NIMessage.parse(Data([0x7F, 0x01])), .unknown(msgId: 0x7F))
    }

    func testParseEmptyDataReturnsNil() {
        XCTAssertNil(NIMessage.parse(Data()))
    }

    func testPhoneToAnchorIdsAreNotParsedAsAnchorMessages() {
        // 0x0A/0x0B/0x0C are phone->anchor; if echoed back they must
        // not match any anchor->phone case
        for id: UInt8 in [0x0A, 0x0B, 0x0C] {
            XCTAssertEqual(NIMessage.parse(Data([id])), .unknown(msgId: id))
        }
    }

    // MARK: - Label decoding

    func testDecodeLabelPlain() {
        XCTAssertEqual(BLE.decodeLabel(Data("desk".utf8)), "desk")
    }

    func testDecodeLabelStripsErasedFlashPadding() {
        // UICR reads as 0xFF when never written
        let data = Data("door".utf8) + Data(repeating: 0xFF, count: 12)
        XCTAssertEqual(BLE.decodeLabel(data), "door")
    }

    func testDecodeLabelStripsNullPadding() {
        let data = Data("bed".utf8) + Data(repeating: 0x00, count: 13)
        XCTAssertEqual(BLE.decodeLabel(data), "bed")
    }

    func testDecodeLabelAllErased() {
        XCTAssertEqual(BLE.decodeLabel(Data(repeating: 0xFF, count: 16)), "")
    }

    func testDecodeLabelEmpty() {
        XCTAssertEqual(BLE.decodeLabel(Data()), "")
    }

    // MARK: - Firmware contract (UUIDs and message IDs)

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

    func testMessageIdConstants() {
        XCTAssertEqual(BLE.msgInitialize, 0x0A)
        XCTAssertEqual(BLE.msgConfigure,  0x0B)
        XCTAssertEqual(BLE.msgStop,       0x0C)
        XCTAssertEqual(BLE.msgAccessoryConfig, 0x01)
        XCTAssertEqual(BLE.msgUwbDidStart,     0x02)
        XCTAssertEqual(BLE.msgUwbDidStop,      0x03)
    }
}
