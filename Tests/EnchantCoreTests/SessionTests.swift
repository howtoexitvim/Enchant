import XCTest
@testable import EnchantCore
final class SessionTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_728_403_200)
    func testPausedTimeIsExcluded() throws {
        var engine = SessionEngine(record: SessionRecord(startedAt: start))
        try engine.pause(at: start.addingTimeInterval(20))
        XCTAssertEqual(engine.record.activeDuration(at: start.addingTimeInterval(50)), 20)
        try engine.resume(at: start.addingTimeInterval(50))
        try engine.finish(at: start.addingTimeInterval(80))
        XCTAssertEqual(engine.record.activeDuration(at: start.addingTimeInterval(900)), 50)
    }
    func testDoublePauseAndFinishedResumeAreRejected() throws {
        var engine = SessionEngine(record: SessionRecord(startedAt: start))
        try engine.pause(at: start.addingTimeInterval(10))
        XCTAssertThrowsError(try engine.pause(at: start.addingTimeInterval(12)))
        try engine.finish(at: start.addingTimeInterval(15))
        XCTAssertThrowsError(try engine.resume(at: start.addingTimeInterval(20)))
    }
    func testRecoveryDoesNotCountAppDowntime() throws {
        var engine = SessionEngine(record: SessionRecord(startedAt: start))
        engine.checkpoint(at: start.addingTimeInterval(12)); engine.recover()
        XCTAssertEqual(engine.record.phase, .interrupted)
        XCTAssertEqual(engine.record.activeDuration(at: start.addingTimeInterval(500)), 12)
        try engine.resume(at: start.addingTimeInterval(500))
        try engine.finish(at: start.addingTimeInterval(510))
        XCTAssertEqual(engine.record.activeDuration(at: start.addingTimeInterval(600)), 22)
    }
    func testCrossMidnightRecordKeepsStartDateInCapturedZone() {
        let d = ISO8601DateFormatter().date(from: "2026-10-08T15:58:00Z")!
        var record = SessionRecord(startedAt: d, timeZoneID: "Asia/Hong_Kong")
        record.endedAt = d.addingTimeInterval(600)
        XCTAssertEqual(record.dayKey, "2026-10-08")
    }
    func testHeartChartBreaksAtPausesAndSamplingGaps() {
        var record = SessionRecord(startedAt: start)
        record.endedAt = start.addingTimeInterval(300)
        record.pauses = [PauseSpan(start: start.addingTimeInterval(20), end: start.addingTimeInterval(80))]
        record.heartSamples = [0, 10, 30, 85, 95, 200].map { HeartSample(date: start.addingTimeInterval(Double($0)), bpm: 100, source: "Watch") }
        XCTAssertEqual(record.heartSegments.map(\.count), [2, 2, 1])
        XCTAssertEqual(record.averageHeartRate, 100)
    }
    func testMissingAndInvalidSamplesDoNotInventHeartRate() {
        var engine = SessionEngine(record: SessionRecord(startedAt: start))
        XCTAssertNil(engine.record.averageHeartRate)
        engine.addHeartSample(HeartSample(date: start, bpm: .nan, source: "Watch"))
        engine.addHeartSample(HeartSample(date: start, bpm: -10, source: "Watch"))
        XCTAssertTrue(engine.record.heartSamples.isEmpty)
    }
    func testUnsafeOrIncompleteLinksAreRejected() throws {
        for url in ["javascript:alert(1)", "file:///tmp/test", "https://", "https://user:password@example.com"] { XCTAssertThrowsError(try RecordLink(title: "", url: url)) }
        XCTAssertEqual(try RecordLink(title: "网页", url: " https://example.com/a ").url, "https://example.com/a")
    }
    func testInvalidTimesAndPauseRangesAreRejected() {
        var record = SessionRecord(startedAt: start)
        record.endedAt = start.addingTimeInterval(-1)
        XCTAssertThrowsError(try record.validate())
        record.endedAt = start.addingTimeInterval(30)
        record.pauses = [PauseSpan(start: start.addingTimeInterval(20), end: start.addingTimeInterval(10))]
        XCTAssertThrowsError(try record.validate())
    }
}
