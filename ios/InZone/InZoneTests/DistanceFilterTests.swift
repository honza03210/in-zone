import XCTest
@testable import InZone

final class DistanceFilterTests: XCTestCase {

    private var filter: DistanceFilter!
    private var t0: Date!

    override func setUp() {
        super.setUp()
        filter = DistanceFilter()
        filter.alpha = 0.3
        filter.maxJump = 3.0
        t0 = Date()
    }

    private func time(_ offset: TimeInterval) -> Date {
        t0.addingTimeInterval(offset)
    }

    // MARK: - Basic

    func testFirstSamplePassesThrough() {
        let result = filter.update(2.5, at: t0)
        XCTAssertEqual(result, 2.5, accuracy: 0.001)
    }

    func testEMASmoothing() {
        filter.maxJump = 1000  // isolate the EMA math from the outlier gate
        _ = filter.update(1.0, at: time(0))
        let result = filter.update(2.0, at: time(0.1))
        // EMA: 0.3 * 2.0 + 0.7 * 1.0 = 1.3
        XCTAssertEqual(result, 1.3, accuracy: 0.001)
    }

    func testConvergesToStableValue() {
        filter.maxJump = 1000  // isolate the EMA math from the outlier gate
        _ = filter.update(1.0, at: time(0))
        var result: Float = 1.0
        for i in 1...50 {
            result = filter.update(3.0, at: time(Double(i) * 0.1))
        }
        XCTAssertEqual(result, 3.0, accuracy: 0.05, "Should converge near 3.0")
    }

    // MARK: - Outlier rejection

    func testOutlierRejected() {
        _ = filter.update(1.0, at: time(0))
        // dt = 0.1s, maxJump = 3.0 m/s, maxDelta = 0.3m
        // Jump of 5.0m >> 0.3m → rejected
        let result = filter.update(6.0, at: time(0.1))
        XCTAssertEqual(result, 1.0, accuracy: 0.001, "Outlier should return previous value")
    }

    func testJustWithinMaxJumpAccepted() {
        _ = filter.update(1.0, at: time(0))
        // dt = 1.0s, maxDelta = 3.0 * 1.0 = 3.0m
        // Jump of 2.5m < 3.0m → accepted
        let result = filter.update(3.5, at: time(1.0))
        // EMA: 0.3 * 3.5 + 0.7 * 1.0 = 1.75
        XCTAssertEqual(result, 1.75, accuracy: 0.001)
    }

    func testJustOverMaxJumpRejected() {
        _ = filter.update(1.0, at: time(0))
        // dt = 1.0s, maxDelta = 3.0m. Jump of 3.1m > 3.0m → rejected
        let result = filter.update(4.1, at: time(1.0))
        XCTAssertEqual(result, 1.0, accuracy: 0.001)
    }

    func testLargeTimeGapAllowsBigJump() {
        _ = filter.update(1.0, at: time(0))
        // dt = 10s, maxDelta = 3.0 * 10 = 30m
        let result = filter.update(20.0, at: time(10.0))
        // 19m jump < 30m → accepted
        XCTAssertNotEqual(result, 1.0, "Large time gap should allow big jump")
    }

    // MARK: - Reset

    func testResetClearsState() {
        _ = filter.update(1.0, at: time(0))
        _ = filter.update(1.5, at: time(0.1))
        filter.reset()

        let result = filter.update(5.0, at: time(0.2))
        XCTAssertEqual(result, 5.0, accuracy: 0.001,
                        "After reset, first sample should pass through")
    }

    // MARK: - Custom alpha

    func testHighAlphaFollowsFast() {
        filter.alpha = 0.9
        filter.maxJump = 1000  // isolate the EMA math from the outlier gate
        _ = filter.update(1.0, at: time(0))
        let result = filter.update(2.0, at: time(0.1))
        // EMA: 0.9 * 2.0 + 0.1 * 1.0 = 1.9
        XCTAssertEqual(result, 1.9, accuracy: 0.001)
    }

    func testLowAlphaFollowsSlow() {
        filter.alpha = 0.1
        filter.maxJump = 1000  // isolate the EMA math from the outlier gate
        _ = filter.update(1.0, at: time(0))
        let result = filter.update(2.0, at: time(0.1))
        // EMA: 0.1 * 2.0 + 0.9 * 1.0 = 1.1
        XCTAssertEqual(result, 1.1, accuracy: 0.001)
    }

    // MARK: - Edge cases

    func testMinimumDtFloor() {
        // Two samples at the same instant — dt clamped to 0.01
        _ = filter.update(1.0, at: t0)
        let result = filter.update(1.02, at: t0)
        // maxDelta = 3.0 * 0.01 = 0.03. |0.02| < 0.03 → accepted
        XCTAssertNotEqual(result, 1.0)
    }
}
