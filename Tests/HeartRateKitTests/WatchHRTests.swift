import XCTest
@testable import HeartRateKit

final class WatchHRTests: XCTestCase {

    // MARK: - HRThrottle

    func testHighResolutionForwardsEverySample() {
        var t = HRThrottle(resolution: .high)
        let base = Date()
        XCTAssertTrue(t.shouldForward(at: base))
        XCTAssertTrue(t.shouldForward(at: base.addingTimeInterval(0.1)))
        XCTAssertTrue(t.shouldForward(at: base.addingTimeInterval(0.2)))
    }

    func testLowResolutionThrottlesWithinInterval() {
        var t = HRThrottle(resolution: .low)   // 5s min interval
        let base = Date()
        XCTAssertTrue(t.shouldForward(at: base), "first sample always forwards")
        XCTAssertFalse(t.shouldForward(at: base.addingTimeInterval(1)), "within 5s suppressed")
        XCTAssertFalse(t.shouldForward(at: base.addingTimeInterval(4.9)), "still within 5s")
        XCTAssertTrue(t.shouldForward(at: base.addingTimeInterval(5)), "at 5s forwards again")
    }

    // MARK: - WatchHRMessage codec

    func testMessageRoundTrip() {
        let time = Date(timeIntervalSince1970: 1_700_000_000)
        let dict = WatchHRMessage.encode(bpm: 72, at: time)
        let decoded = WatchHRMessage.decode(dict)
        XCTAssertEqual(decoded?.bpm, 72)
        XCTAssertEqual(decoded?.time.timeIntervalSince1970 ?? 0, time.timeIntervalSince1970, accuracy: 0.001)
    }

    func testDecodeBpmMissingReturnsNil() {
        XCTAssertNil(WatchHRMessage.decodeBpm(["nope": 1]))
        XCTAssertNil(WatchHRMessage.decode(["nope": 1]))
    }

    func testResolutionMinInterval() {
        XCTAssertEqual(HRResolution.high.minInterval, 0)
        XCTAssertEqual(HRResolution.low.minInterval, 5)
    }
}
