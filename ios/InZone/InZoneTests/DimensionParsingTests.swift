import XCTest
@testable import InZone

final class DimensionParsingTests: XCTestCase {

    func testParsesDotDecimal() {
        XCTAssertEqual(RoomSetupView.parseDimension("4.5"), 4.5)
    }

    func testParsesCommaDecimal() {
        XCTAssertEqual(RoomSetupView.parseDimension("4,5"), 4.5)
    }

    func testParsesInteger() {
        XCTAssertEqual(RoomSetupView.parseDimension("5"), 5.0)
    }

    func testRejectsGarbage() {
        XCTAssertNil(RoomSetupView.parseDimension("abc"))
        XCTAssertNil(RoomSetupView.parseDimension(""))
    }
}
