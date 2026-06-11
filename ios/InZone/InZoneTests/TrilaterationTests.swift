import XCTest
@testable import InZone

final class TrilaterationTests: XCTestCase {

    private let corners: [AnchorPlacement] = [
        AnchorPlacement(id: 0, x: 0, y: 0, label: "A"),
        AnchorPlacement(id: 1, x: 5, y: 0, label: "B"),
        AnchorPlacement(id: 2, x: 5, y: 4, label: "C"),
        AnchorPlacement(id: 3, x: 0, y: 4, label: "D"),
    ]

    // MARK: - Basic trilateration

    func testCenterOfRoom() {
        // Phone at (2.5, 2.0) — center of 5×4 room
        let dists: [UInt8: Float] = [
            0: sqrt(2.5*2.5 + 2.0*2.0),     // dist to (0,0)
            1: sqrt(2.5*2.5 + 2.0*2.0),     // dist to (5,0)
            2: sqrt(2.5*2.5 + 2.0*2.0),     // dist to (5,4)
            3: sqrt(2.5*2.5 + 2.0*2.0),     // dist to (0,4)
        ]
        let pos = Trilateration.estimatePosition(distances: dists, anchors: corners)
        XCTAssertNotNil(pos)
        XCTAssertEqual(Float(pos!.x), 2.5, accuracy: 0.01)
        XCTAssertEqual(Float(pos!.y), 2.0, accuracy: 0.01)
    }

    func testCornerPosition() {
        // Phone right at anchor 0 (0, 0)
        let dists: [UInt8: Float] = [
            0: 0.01,   // ~at anchor 0
            1: 5.0,    // dist to (5,0)
            2: sqrt(25 + 16), // dist to (5,4)
            3: 4.0,    // dist to (0,4)
        ]
        let pos = Trilateration.estimatePosition(distances: dists, anchors: corners)
        XCTAssertNotNil(pos)
        XCTAssertEqual(Float(pos!.x), 0.0, accuracy: 0.15)
        XCTAssertEqual(Float(pos!.y), 0.0, accuracy: 0.15)
    }

    func testKnownPosition() {
        // Phone at (1, 1)
        let dists: [UInt8: Float] = [
            0: sqrt(2),         // dist to (0,0)
            1: sqrt(16 + 1),    // dist to (5,0)
            2: sqrt(16 + 9),    // dist to (5,4)
            3: sqrt(1 + 9),     // dist to (0,4)
        ]
        let pos = Trilateration.estimatePosition(distances: dists, anchors: corners)
        XCTAssertNotNil(pos)
        XCTAssertEqual(Float(pos!.x), 1.0, accuracy: 0.01)
        XCTAssertEqual(Float(pos!.y), 1.0, accuracy: 0.01)
    }

    // MARK: - Partial anchor coverage

    func testThreeAnchors() {
        // Phone at (2.5, 2.0), only anchors 0,1,2
        let dists: [UInt8: Float] = [
            0: sqrt(2.5*2.5 + 2.0*2.0),
            1: sqrt(2.5*2.5 + 2.0*2.0),
            2: sqrt(2.5*2.5 + 2.0*2.0),
        ]
        let pos = Trilateration.estimatePosition(distances: dists, anchors: corners)
        XCTAssertNotNil(pos)
        XCTAssertEqual(Float(pos!.x), 2.5, accuracy: 0.1)
        XCTAssertEqual(Float(pos!.y), 2.0, accuracy: 0.1)
    }

    func testTwoAnchorsFallsBackToWeightedCentroid() {
        // With only 2 anchors, uses weighted centroid — less accurate
        let dists: [UInt8: Float] = [
            0: 1.0,
            1: 4.0,
        ]
        let pos = Trilateration.estimatePosition(distances: dists, anchors: corners)
        XCTAssertNotNil(pos)
        // Weighted centroid: w0 = 1/1 = 1, w1 = 1/16 = 0.0625
        // x = (0*1 + 5*0.0625) / 1.0625 ≈ 0.29
        XCTAssertEqual(Float(pos!.x), 0.0, accuracy: 1.0, "Weighted centroid biases toward closer anchor")
    }

    func testSingleAnchorReturnsNil() {
        let dists: [UInt8: Float] = [0: 2.0]
        let pos = Trilateration.estimatePosition(distances: dists, anchors: corners)
        XCTAssertNil(pos)
    }

    func testNoAnchorsReturnsNil() {
        let pos = Trilateration.estimatePosition(distances: [:], anchors: corners)
        XCTAssertNil(pos)
    }

    func testNonMatchingAnchorsReturnsNil() {
        let dists: [UInt8: Float] = [10: 2.0, 11: 3.0]
        let pos = Trilateration.estimatePosition(distances: dists, anchors: corners)
        XCTAssertNil(pos)
    }

    // MARK: - Fingerprint estimation

    func testEstimateFromFingerprint() {
        let fp: [String: DistanceStats] = [
            "0": DistanceStats(mean: sqrt(2), variance: 0.01, sampleCount: 20),
            "1": DistanceStats(mean: sqrt(17), variance: 0.01, sampleCount: 20),
            "2": DistanceStats(mean: 5, variance: 0.01, sampleCount: 20),
            "3": DistanceStats(mean: sqrt(10), variance: 0.01, sampleCount: 20),
        ]
        let pos = Trilateration.estimateFromFingerprint(fp, anchors: corners)
        XCTAssertNotNil(pos)
        XCTAssertEqual(Float(pos!.x), 1.0, accuracy: 0.05)
        XCTAssertEqual(Float(pos!.y), 1.0, accuracy: 0.05)
    }

    // MARK: - Noise tolerance

    func testToleratesSmallNoise() {
        // Phone at (2.5, 2.0) with ±0.05m noise
        let true_d0 = sqrt(2.5*2.5 + 2.0*2.0)
        let dists: [UInt8: Float] = [
            0: true_d0 + 0.05,
            1: true_d0 - 0.03,
            2: true_d0 + 0.02,
            3: true_d0 - 0.04,
        ]
        let pos = Trilateration.estimatePosition(distances: dists, anchors: corners)
        XCTAssertNotNil(pos)
        XCTAssertEqual(Float(pos!.x), 2.5, accuracy: 0.2)
        XCTAssertEqual(Float(pos!.y), 2.0, accuracy: 0.2)
    }

    // MARK: - Collinear anchors

    func testCollinearAnchorsFallsBackToWeightedCentroid() {
        let line: [AnchorPlacement] = [
            AnchorPlacement(id: 0, x: 0, y: 0, label: "A"),
            AnchorPlacement(id: 1, x: 2, y: 0, label: "B"),
            AnchorPlacement(id: 2, x: 4, y: 0, label: "C"),
        ]
        let dists: [UInt8: Float] = [0: 1.0, 1: 1.0, 2: 3.0]
        let pos = Trilateration.estimatePosition(distances: dists, anchors: line)
        // Collinear → determinant ≈ 0 → falls back to weighted centroid
        XCTAssertNotNil(pos, "Should return weighted centroid for collinear anchors")
    }
}
