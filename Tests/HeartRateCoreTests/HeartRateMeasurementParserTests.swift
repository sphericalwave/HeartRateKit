import XCTest
@testable import HeartRateCore

final class HeartRateMeasurementParserTests: XCTestCase {

    func testEightBitNoOptionalFields() {
        let sample = HeartRateMeasurementParser.parse(Data([0x00, 72]), uptime: 0)
        XCTAssertEqual(sample?.bpm, 72)
        XCTAssertEqual(sample?.contact, .unsupported)
        XCTAssertEqual(sample?.rrIntervals, [])
        XCTAssertNil(sample?.energyExpended)
    }

    func testSixteenBitBpm() {
        let sample = HeartRateMeasurementParser.parse(Data([0x01, 0x2C, 0x01]), uptime: 0)
        XCTAssertEqual(sample?.bpm, 300)
    }

    func testContactDetectedAndSupported() {
        // flags: bit1 (detected) + bit2 (supported) set
        let sample = HeartRateMeasurementParser.parse(Data([0b0000_0110, 80]), uptime: 0)
        XCTAssertEqual(sample?.contact, .detected)
    }

    func testContactSupportedButNotDetected() {
        // flags: bit2 (supported) set, bit1 (detected) clear
        let sample = HeartRateMeasurementParser.parse(Data([0b0000_0100, 80]), uptime: 0)
        XCTAssertEqual(sample?.contact, .notDetected)
    }

    func testEnergyExpendedPresent() {
        // flags bit3 set, energy = 0x0102 = 258
        let sample = HeartRateMeasurementParser.parse(Data([0b0000_1000, 80, 0x02, 0x01]), uptime: 0)
        XCTAssertEqual(sample?.energyExpended, 258)
    }

    func testRRIntervalsPresent() {
        // flags bit4 set, two RR values: 1024 (1.0s) and 512 (0.5s)
        let sample = HeartRateMeasurementParser.parse(
            Data([0b0001_0000, 80, 0x00, 0x04, 0x00, 0x02]), uptime: 0
        )
        XCTAssertEqual(sample?.rrIntervals, [1.0, 0.5])
    }

    func testEnergyAndRRTogether() {
        let sample = HeartRateMeasurementParser.parse(
            Data([0b0001_1000, 80, 0x0A, 0x00, 0x00, 0x04]), uptime: 0
        )
        XCTAssertEqual(sample?.energyExpended, 10)
        XCTAssertEqual(sample?.rrIntervals, [1.0])
    }

    func testMalformedDataReturnsNilNeverCrashes() {
        XCTAssertNil(HeartRateMeasurementParser.parse(Data(), uptime: 0))
        XCTAssertNil(HeartRateMeasurementParser.parse(Data([0x01]), uptime: 0)) // 16-bit flag, truncated
        XCTAssertNil(HeartRateMeasurementParser.parse(Data([0b0000_1000, 80]), uptime: 0)) // energy flag, missing bytes
        XCTAssertNil(HeartRateMeasurementParser.parse(Data([0b0001_0000, 80, 0x00]), uptime: 0)) // RR flag, odd trailing byte
    }
}

final class HRSignalEvaluatorTests: XCTestCase {

    func testGoodWhileFreshAndDetected() {
        var evaluator = HRSignalEvaluator(noContactAfter: 3, staleAfter: 5)
        let t0 = Date()
        evaluator.ingest(HeartRateSample(bpm: 80, contact: .detected, rrIntervals: [], energyExpended: nil, timestamp: t0, uptime: 0))
        XCTAssertEqual(evaluator.state(now: t0, connected: true), .good)
    }

    func testNoContactAfterThreshold() {
        var evaluator = HRSignalEvaluator(noContactAfter: 3, staleAfter: 5)
        let t0 = Date()
        evaluator.ingest(HeartRateSample(bpm: 80, contact: .detected, rrIntervals: [], energyExpended: nil, timestamp: t0, uptime: 0))
        evaluator.ingest(HeartRateSample(bpm: 80, contact: .notDetected, rrIntervals: [], energyExpended: nil, timestamp: t0.addingTimeInterval(1), uptime: 1))
        XCTAssertEqual(evaluator.state(now: t0.addingTimeInterval(4), connected: true), .noContact)
    }

    func testStaleAfterNoPackets() {
        var evaluator = HRSignalEvaluator(noContactAfter: 3, staleAfter: 5)
        let t0 = Date()
        evaluator.ingest(HeartRateSample(bpm: 80, contact: .detected, rrIntervals: [], energyExpended: nil, timestamp: t0, uptime: 0))
        XCTAssertEqual(evaluator.state(now: t0.addingTimeInterval(6), connected: true), .stale)
    }

    func testDisconnectedWhenNotConnected() {
        let evaluator = HRSignalEvaluator()
        XCTAssertEqual(evaluator.state(now: Date(), connected: false), .disconnected)
    }
}

final class MockHeartRateSourceTests: XCTestCase {

    func testSteadyProfile() {
        XCTAssertEqual(MockHeartRateSource.bpm(for: .steady(bpm: 90), elapsed: 42), 90)
    }

    func testRampProfile() {
        XCTAssertEqual(MockHeartRateSource.bpm(for: .ramp(from: 60, to: 160, duration: 10), elapsed: 0), 60)
        XCTAssertEqual(MockHeartRateSource.bpm(for: .ramp(from: 60, to: 160, duration: 10), elapsed: 10), 160)
        XCTAssertEqual(MockHeartRateSource.bpm(for: .ramp(from: 60, to: 160, duration: 10), elapsed: 5), 110)
    }

    func testSpikeProfile() {
        let profile = MockHeartRateSource.Profile.spike(baseline: 100, peak: 180, at: 5, duration: 2)
        XCTAssertEqual(MockHeartRateSource.bpm(for: profile, elapsed: 4), 100)
        XCTAssertEqual(MockHeartRateSource.bpm(for: profile, elapsed: 6), 180)
        XCTAssertEqual(MockHeartRateSource.bpm(for: profile, elapsed: 8), 100)
    }

    func testDropoutProfile() {
        let profile = MockHeartRateSource.Profile.dropout(bpm: 100, from: 5, duration: 3)
        XCTAssertEqual(MockHeartRateSource.bpm(for: profile, elapsed: 4), 100)
        XCTAssertNil(MockHeartRateSource.bpm(for: profile, elapsed: 6))
        XCTAssertEqual(MockHeartRateSource.bpm(for: profile, elapsed: 9), 100)
    }
}
