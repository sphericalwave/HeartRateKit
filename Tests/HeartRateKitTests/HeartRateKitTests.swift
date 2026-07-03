import XCTest
@testable import HeartRateKit

private final class StubSource: HeartRateSource {
    let samples: AsyncStream<Int>
    private let continuation: AsyncStream<Int>.Continuation
    init() {
        var c: AsyncStream<Int>.Continuation!
        samples = AsyncStream { c = $0 }
        continuation = c
    }
    func start() async throws {}
    func stop() { continuation.finish() }
    func emit(_ bpm: Int) { continuation.yield(bpm) }
}

final class BLEParserTests: XCTestCase {

    func testEightBitMeasurement() {
        // flags 0x00 → UInt8 bpm
        XCTAssertEqual(BLEHeartRateSource.parseHeartRateMeasurement(Data([0x00, 72])), 72)
        XCTAssertEqual(BLEHeartRateSource.parseHeartRateMeasurement(Data([0x00, 255])), 255)
    }

    func testSixteenBitMeasurement() {
        // flags 0x01 → UInt16 little-endian bpm
        XCTAssertEqual(BLEHeartRateSource.parseHeartRateMeasurement(Data([0x01, 0x2C, 0x01])), 300)
        XCTAssertEqual(BLEHeartRateSource.parseHeartRateMeasurement(Data([0x01, 72, 0x00])), 72)
    }

    func testTruncatedOrEmptyData() {
        XCTAssertEqual(BLEHeartRateSource.parseHeartRateMeasurement(Data()), 0)
        XCTAssertEqual(BLEHeartRateSource.parseHeartRateMeasurement(Data([0x00])), 0)
        // Truncated 16-bit measurement falls back to the 8-bit read
        // (longstanding parser behavior, preserved on extraction).
        XCTAssertEqual(BLEHeartRateSource.parseHeartRateMeasurement(Data([0x01, 72])), 72)
    }
}

final class HRRecorderTests: XCTestCase {

    @MainActor
    func testSessionStatsMinAvgMax() async {
        let recorder = HRRecorder()
        let source = StubSource()
        recorder.attach(source)
        recorder.beginSession()

        for bpm in [60, 80, 100] { source.emit(bpm) }
        // Let the ingestion task drain the stream.
        try? await Task.sleep(nanoseconds: 100_000_000)

        let stats = recorder.endSession()
        XCTAssertEqual(stats?.min, 60)
        XCTAssertEqual(stats?.avg, 80)
        XCTAssertEqual(stats?.max, 100)
        XCTAssertEqual(stats?.count, 3)
        XCTAssertEqual(recorder.latestBpm, 100)
        recorder.detach()
    }

    @MainActor
    func testEndSessionWithoutSamplesIsNil() {
        let recorder = HRRecorder()
        recorder.beginSession()
        XCTAssertNil(recorder.endSession())
    }

    @MainActor
    func testSamplesOutsideSessionAreNotRecorded() async {
        let recorder = HRRecorder()
        let source = StubSource()
        recorder.attach(source)

        source.emit(70)  // before beginSession
        try? await Task.sleep(nanoseconds: 100_000_000)

        recorder.beginSession()
        XCTAssertNil(recorder.endSession())  // nothing captured in-session
        XCTAssertEqual(recorder.latestBpm, 70)  // but live state updated
        recorder.detach()
    }
}
