import XCTest
@testable import InZone

final class ZoneEngineTests: XCTestCase {

    private var engine: ZoneEngine!

    override func setUp() {
        super.setUp()
        engine = ZoneEngine()
        engine.isDetecting = true
        engine.dwellTime = 0
        engine.hysteresisMargin = 0.5
        engine.maxZoneRadius = 3.0
    }

    // MARK: - Helpers

    private func makeZone(name: String, distances: [UInt8: Float]) -> Zone {
        var fp: [String: DistanceStats] = [:]
        for (id, dist) in distances {
            fp[String(id)] = DistanceStats(mean: dist, variance: 0.01, sampleCount: 20)
        }
        return Zone(id: UUID(), name: name, fingerprint: fp,
                     capturedAt: Date(), colorName: "blue")
    }

    private func detect(_ distances: [UInt8: Float], zones: [Zone], times: Int = 2) {
        for _ in 0..<times {
            engine.update(distances: distances, zones: zones)
        }
    }

    // MARK: - Guard clauses

    func testNoDetectionWhenDisabled() {
        engine.isDetecting = false
        let zone = makeZone(name: "desk", distances: [0: 1.0, 1: 2.0])
        detect([0: 1.0, 1: 2.0], zones: [zone])
        XCTAssertNil(engine.currentZone)
    }

    func testNoDetectionWithEmptyZones() {
        detect([0: 1.0, 1: 2.0], zones: [])
        XCTAssertNil(engine.currentZone)
    }

    func testNoDetectionWithEmptyDistances() {
        let zone = makeZone(name: "desk", distances: [0: 1.0])
        detect([:], zones: [zone])
        XCTAssertNil(engine.currentZone)
    }

    // MARK: - Basic matching

    func testExactMatchDetectsZone() {
        let zone = makeZone(name: "desk", distances: [0: 1.0, 1: 2.0, 2: 3.0, 3: 4.0])
        detect([0: 1.0, 1: 2.0, 2: 3.0, 3: 4.0], zones: [zone])
        XCTAssertEqual(engine.currentZone?.name, "desk")
    }

    func testClosestZoneWins() {
        let desk = makeZone(name: "desk", distances: [0: 1.0, 1: 1.0, 2: 1.0, 3: 1.0])
        let bed  = makeZone(name: "bed",  distances: [0: 4.0, 1: 4.0, 2: 4.0, 3: 4.0])
        detect([0: 1.1, 1: 0.9, 2: 1.0, 3: 1.1], zones: [desk, bed])
        XCTAssertEqual(engine.currentZone?.name, "desk")
    }

    func testZoneTooFarReturnsNil() {
        engine.maxZoneRadius = 1.0
        let zone = makeZone(name: "desk", distances: [0: 1.0, 1: 1.0])
        detect([0: 5.0, 1: 5.0], zones: [zone])
        XCTAssertNil(engine.currentZone)
    }

    func testSingleAnchorZone() {
        let zone = makeZone(name: "corner", distances: [2: 1.5])
        detect([0: 3.0, 1: 2.0, 2: 1.5, 3: 4.0], zones: [zone])
        XCTAssertEqual(engine.currentZone?.name, "corner")
    }

    func testPartialAnchorOverlap() {
        let zone = makeZone(name: "desk", distances: [0: 1.0, 1: 2.0, 2: 3.0, 3: 4.0])
        // Only reporting anchors 0 and 1 — engine uses those two
        detect([0: 1.0, 1: 2.0], zones: [zone])
        XCTAssertEqual(engine.currentZone?.name, "desk")
    }

    func testNoOverlapReturnsInfinity() {
        // Zone uses anchors 0,1 but readings only have 2,3
        let zone = makeZone(name: "desk", distances: [0: 1.0, 1: 2.0])
        detect([2: 1.0, 3: 2.0], zones: [zone])
        XCTAssertNil(engine.currentZone)
    }

    // MARK: - Dwell time

    func testDwellTimeRequired() {
        engine.dwellTime = 100
        let zone = makeZone(name: "desk", distances: [0: 1.0, 1: 2.0])
        detect([0: 1.0, 1: 2.0], zones: [zone], times: 5)
        XCTAssertNil(engine.currentZone, "Should not detect before dwell time elapses")
    }

    func testDwellTimeZeroDetectsOnSecondUpdate() {
        engine.dwellTime = 0
        let zone = makeZone(name: "desk", distances: [0: 1.0, 1: 2.0])

        engine.update(distances: [0: 1.0, 1: 2.0], zones: [zone])
        XCTAssertNil(engine.currentZone, "First update sets candidate, not zone")

        engine.update(distances: [0: 1.0, 1: 2.0], zones: [zone])
        XCTAssertEqual(engine.currentZone?.name, "desk", "Second update should confirm")
    }

    // MARK: - Hysteresis

    func testHysteresisPreventsFlickering() {
        engine.hysteresisMargin = 2.0
        let desk = makeZone(name: "desk", distances: [0: 2.0])
        let bed  = makeZone(name: "bed",  distances: [0: 2.3])
        // Distance to desk: |2.1 - 2.0| = 0.1, to bed: |2.1 - 2.3| = 0.2
        // Margin: 0.2 - 0.1 = 0.1, which is < hysteresisMargin (2.0)
        detect([0: 2.1], zones: [desk, bed], times: 5)
        XCTAssertNil(engine.currentZone, "Margin too small for hysteresis threshold")
    }

    func testHysteresisPassesWithLargeMargin() {
        engine.hysteresisMargin = 0.1
        let desk = makeZone(name: "desk", distances: [0: 1.0])
        let bed  = makeZone(name: "bed",  distances: [0: 5.0])
        // Distance to desk: |1.0 - 1.0| = 0, to bed: |1.0 - 5.0| = 4.0
        // Margin: 4.0 - 0 = 4.0, which is >> hysteresisMargin (0.1)
        detect([0: 1.0], zones: [desk, bed])
        XCTAssertEqual(engine.currentZone?.name, "desk")
    }

    // MARK: - Zone stability

    func testStaysInCurrentZone() {
        let zone = makeZone(name: "desk", distances: [0: 1.0, 1: 2.0])
        detect([0: 1.0, 1: 2.0], zones: [zone])
        XCTAssertEqual(engine.currentZone?.name, "desk")

        // Keep updating with same distances — should stay
        for _ in 0..<10 {
            engine.update(distances: [0: 1.0, 1: 2.0], zones: [zone])
        }
        XCTAssertEqual(engine.currentZone?.name, "desk")
    }

    func testSwitchToNewZoneAfterDwell() {
        let desk = makeZone(name: "desk", distances: [0: 1.0])
        let bed  = makeZone(name: "bed",  distances: [0: 5.0])
        engine.hysteresisMargin = 0.1

        detect([0: 1.0], zones: [desk, bed])
        XCTAssertEqual(engine.currentZone?.name, "desk")

        // Move to bed
        detect([0: 5.0], zones: [desk, bed])
        XCTAssertEqual(engine.currentZone?.name, "bed")
    }

    func testCurrentZonePersistsOnEmptyDistances() {
        let zone = makeZone(name: "desk", distances: [0: 1.0])
        detect([0: 1.0], zones: [zone])
        XCTAssertEqual(engine.currentZone?.name, "desk")

        // Empty distances — guard returns early, zone persists
        engine.update(distances: [:], zones: [zone])
        XCTAssertEqual(engine.currentZone?.name, "desk")
    }

    func testZoneClearsWhenAllTooFar() {
        engine.maxZoneRadius = 1.0
        let zone = makeZone(name: "desk", distances: [0: 1.0])

        // Detect the zone first
        detect([0: 1.0], zones: [zone])
        XCTAssertEqual(engine.currentZone?.name, "desk")

        // Move far away — zone should clear
        engine.update(distances: [0: 10.0], zones: [zone])
        XCTAssertNil(engine.currentZone)
    }

    // MARK: - Confidence

    func testConfidenceWithSingleZone() {
        let zone = makeZone(name: "desk", distances: [0: 1.0])
        detect([0: 1.0], zones: [zone])
        // Single zone: margin = maxZoneRadius (no second-best)
        // confidence = min(1, 3.0 / 0.5) = 1.0
        XCTAssertEqual(engine.zoneConfidence, 1.0, accuracy: 0.01)
    }
}
