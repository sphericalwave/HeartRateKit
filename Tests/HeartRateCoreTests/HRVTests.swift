import XCTest
@testable import HeartRateCore

final class HRVTests: XCTestCase {

    func testRMSSDOfKnownSeries() throws {
        // Successive differences: +0.05, -0.05, +0.05 → RMS 0.05 s = 50 ms.
        let value = try XCTUnwrap(HRV.rmssd([0.80, 0.85, 0.80, 0.85]))
        XCTAssertEqual(value, 50, accuracy: 1e-9)
    }

    func testSteadyRhythmIsZero() throws {
        XCTAssertEqual(try XCTUnwrap(HRV.rmssd([1.0, 1.0, 1.0])), 0, accuracy: 1e-12)
    }

    func testTooFewIntervalsIsNil() {
        XCTAssertNil(HRV.rmssd([]))
        XCTAssertNil(HRV.rmssd([0.8]))
        XCTAssertNil(HRV.rmssd([0.8, 0.85]))   // one difference only
    }

    func testImplausibleIntervalsAreDropped() throws {
        // 0.1 s and 3.0 s are out of range; what remains is the known series.
        let value = try XCTUnwrap(HRV.rmssd([0.80, 0.1, 0.85, 3.0, 0.80, 0.85]))
        XCTAssertEqual(value, 50, accuracy: 1e-9)
    }

    func testMissedBeatDifferencesAreSkipped() throws {
        // 1.6 s is a missed beat (doubles the interval); both jumps around it
        // exceed 20% and are skipped, leaving 0.80→0.85 and 0.85→0.80.
        let value = try XCTUnwrap(HRV.rmssd([0.80, 0.85, 1.60, 0.85, 0.80]))
        XCTAssertEqual(value, 50, accuracy: 1e-9)
    }
}
