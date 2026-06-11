import XCTest
@testable import InZone

final class ZoneModelTests: XCTestCase {

    // MARK: - Codable round-trip

    func testSingleZoneRoundTrip() throws {
        let zone = Zone(
            id: UUID(),
            name: "desk",
            fingerprint: [
                "0": DistanceStats(mean: 1.23, variance: 0.05, sampleCount: 20),
                "1": DistanceStats(mean: 2.45, variance: 0.08, sampleCount: 18),
                "2": DistanceStats(mean: 3.67, variance: 0.12, sampleCount: 22),
                "3": DistanceStats(mean: 0.89, variance: 0.02, sampleCount: 15),
            ],
            capturedAt: Date(timeIntervalSince1970: 1718100000),
            colorName: "purple"
        )

        let data = try JSONEncoder().encode(zone)
        let decoded = try JSONDecoder().decode(Zone.self, from: data)

        XCTAssertEqual(decoded.id, zone.id)
        XCTAssertEqual(decoded.name, "desk")
        XCTAssertEqual(decoded.colorName, "purple")
        XCTAssertEqual(decoded.fingerprint.count, 4)
        let a2 = try XCTUnwrap(decoded.fingerprint["2"])
        XCTAssertEqual(a2.mean, 3.67, accuracy: 0.001)
        XCTAssertEqual(a2.sampleCount, 22)
    }

    func testMultipleZonesRoundTrip() throws {
        let zones = [
            Zone(id: UUID(), name: "desk",
                 fingerprint: ["0": DistanceStats(mean: 1.0, variance: 0.1, sampleCount: 10)],
                 capturedAt: Date(), colorName: "blue"),
            Zone(id: UUID(), name: "bed",
                 fingerprint: ["1": DistanceStats(mean: 2.0, variance: 0.2, sampleCount: 15)],
                 capturedAt: Date(), colorName: "green"),
        ]

        let data = try JSONEncoder().encode(zones)
        let decoded = try JSONDecoder().decode([Zone].self, from: data)

        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded[0].name, "desk")
        XCTAssertEqual(decoded[1].name, "bed")
    }

    func testEmptyFingerprintRoundTrip() throws {
        let zone = Zone(id: UUID(), name: "empty",
                         fingerprint: [:],
                         capturedAt: Date(), colorName: "red")

        let data = try JSONEncoder().encode(zone)
        let decoded = try JSONDecoder().decode(Zone.self, from: data)

        XCTAssertEqual(decoded.fingerprint.count, 0)
    }

    // MARK: - Stats accessor

    func testStatsForAnchorId() {
        let zone = Zone(
            id: UUID(), name: "test",
            fingerprint: [
                "0": DistanceStats(mean: 1.5, variance: 0.1, sampleCount: 10),
                "3": DistanceStats(mean: 4.2, variance: 0.3, sampleCount: 8),
            ],
            capturedAt: Date(), colorName: "blue"
        )

        XCTAssertEqual(zone.stats(for: 0)?.mean, 1.5)
        XCTAssertEqual(zone.stats(for: 3)?.mean, 4.2)
        XCTAssertNil(zone.stats(for: 1))
        XCTAssertNil(zone.stats(for: 255))
    }

    // MARK: - DistanceStats

    func testDistanceStatsCodable() throws {
        let stats = DistanceStats(mean: 2.718, variance: 0.314, sampleCount: 42)
        let data = try JSONEncoder().encode(stats)
        let decoded = try JSONDecoder().decode(DistanceStats.self, from: data)

        XCTAssertEqual(decoded.mean, 2.718, accuracy: 0.0001)
        XCTAssertEqual(decoded.variance, 0.314, accuracy: 0.0001)
        XCTAssertEqual(decoded.sampleCount, 42)
    }

    // MARK: - JSON structure

    func testFingerprintEncodesAsObject() throws {
        let zone = Zone(
            id: UUID(), name: "test",
            fingerprint: ["0": DistanceStats(mean: 1.0, variance: 0.1, sampleCount: 5)],
            capturedAt: Date(), colorName: "blue"
        )

        let data = try JSONEncoder().encode(zone)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let fp = json?["fingerprint"] as? [String: Any]

        XCTAssertNotNil(fp, "Fingerprint should encode as a JSON object")
        XCTAssertNotNil(fp?["0"], "Keys should be string anchor IDs")
    }
}
