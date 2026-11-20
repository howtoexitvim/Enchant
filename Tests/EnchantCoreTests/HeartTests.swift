import XCTest
@testable import EnchantCore

final class HeartTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_728_403_200)

    // Rejecting by delivery phase loses genuine readings measured before the pause.
    func testDelayedPrePauseMeasurementIsRetainedWhilePaused() throws {
        var engine = SessionEngine(record: SessionRecord(startedAt: start))
        try engine.pause(at: start.addingTimeInterval(20))
        engine.addHeartSample(HeartSample(date: start.addingTimeInterval(10), bpm: 90, source: "Sensor"))
        XCTAssertEqual(engine.record.heartSamples.count, 1)
        XCTAssertEqual(engine.record.averageHeartRate, 90)
        XCTAssertEqual(engine.record.lastCheckpoint, start.addingTimeInterval(20))
    }

    // Accepting by delivery phase lets a paused measurement enter raw counts and peaks.
    func testPausedMeasurementDeliveredAfterResumeIsExcluded() throws {
        var engine = SessionEngine(record: SessionRecord(startedAt: start))
        try engine.pause(at: start.addingTimeInterval(20))
        try engine.resume(at: start.addingTimeInterval(40))
        engine.addHeartSample(HeartSample(date: start.addingTimeInterval(30), bpm: 200, source: "Sensor"))
        XCTAssertTrue(engine.record.heartSamples.isEmpty)
        XCTAssertNil(engine.record.averageHeartRate)
    }

    // Repeated delivery must not give one physical measurement additional statistical weight.
    func testRepeatedMeasurementDoesNotBiasAverage() {
        var engine = SessionEngine(record: SessionRecord(startedAt: start))
        let first = HeartSample(date: start.addingTimeInterval(10), bpm: 80, source: "Sensor")
        engine.addHeartSample(first)
        engine.addHeartSample(first)
        engine.addHeartSample(HeartSample(date: start.addingTimeInterval(20), bpm: 120, source: "Sensor"))
        XCTAssertEqual(engine.record.heartSamples.count, 2)
        XCTAssertEqual(engine.record.averageHeartRate, 100)
    }

    // Canonical HealthKit identity survives source display-name changes between deliveries.
    func testCanonicalIdentityPreventsRepeatedSeriesEntry() {
        var engine = SessionEngine(record: SessionRecord(startedAt: start))
        engine.addHeartSample(HeartSample(date: start.addingTimeInterval(10), bpm: 80, source: "Sensor", identity: "container-A:entry-1"))
        engine.addHeartSample(HeartSample(date: start.addingTimeInterval(10), bpm: 80, source: "Sensor renamed", identity: "container-A:entry-1"))
        engine.addHeartSample(HeartSample(date: start.addingTimeInterval(20), bpm: 120, source: "Sensor", identity: "container-A:entry-2"))
        XCTAssertEqual(engine.record.heartSamples.count, 2)
        XCTAssertEqual(engine.record.averageHeartRate, 100)
    }

    // Equal values at the same time can come from distinct physical containers.
    func testDistinctCanonicalMeasurementsAreNotCollapsedByValue() {
        var engine = SessionEngine(record: SessionRecord(startedAt: start))
        engine.addHeartSample(HeartSample(date: start.addingTimeInterval(10), bpm: 80, source: "Sensor", identity: "container-A:entry-1"))
        engine.addHeartSample(HeartSample(date: start.addingTimeInterval(10), bpm: 80, source: "Sensor", identity: "container-B:entry-1"))
        XCTAssertEqual(engine.record.heartSamples.count, 2)
    }

    func testResumeBoundaryMeasurementIsActive() throws {
        var engine = SessionEngine(record: SessionRecord(startedAt: start))
        try engine.pause(at: start.addingTimeInterval(20))
        try engine.resume(at: start.addingTimeInterval(40))
        engine.addHeartSample(HeartSample(date: start.addingTimeInterval(40), bpm: 90, source: "Sensor"))
        XCTAssertEqual(engine.record.averageHeartRate, 90)
    }

    func testLateSystemPauseAndResumeUseEventDates() throws {
        var engine = SessionEngine(record: SessionRecord(startedAt: start))
        engine.checkpoint(at: start.addingTimeInterval(100))
        engine.systemPause(at: start.addingTimeInterval(20))
        XCTAssertEqual(engine.record.phase, .paused)
        XCTAssertEqual(engine.record.activeDuration(at: start.addingTimeInterval(120)), 20)
        engine.systemResume(at: start.addingTimeInterval(80))
        XCTAssertEqual(engine.record.activeDuration(at: start.addingTimeInterval(110)), 50)
        XCTAssertEqual(engine.record.lastCheckpoint, start.addingTimeInterval(100))
        XCTAssertNoThrow(try engine.record.validate())
    }

    func testLateSystemInterruptionStopsAtEventDate() throws {
        var engine = SessionEngine(record: SessionRecord(startedAt: start))
        engine.addHeartSample(HeartSample(date: start.addingTimeInterval(10), bpm: 80, source: "Sensor"))
        engine.addHeartSample(HeartSample(date: start.addingTimeInterval(90), bpm: 120, source: "Sensor"))
        try engine.pause(at: start.addingTimeInterval(100))
        engine.interrupt(at: start.addingTimeInterval(20))
        XCTAssertEqual(engine.record.phase, .interrupted)
        XCTAssertEqual(engine.record.endedAt, start.addingTimeInterval(20))
        XCTAssertEqual(engine.record.activeDuration(at: start.addingTimeInterval(500)), 20)
        XCTAssertEqual(engine.record.heartSamples.count, 1)
        XCTAssertEqual(engine.record.averageHeartRate, 80)
        XCTAssertTrue(engine.record.pauses.isEmpty)
        XCTAssertNoThrow(try engine.record.validate())
    }

    func testUserPauseStillRejectsEarlierThanCheckpoint() {
        var engine = SessionEngine(record: SessionRecord(startedAt: start))
        engine.checkpoint(at: start.addingTimeInterval(100))
        XCTAssertThrowsError(try engine.pause(at: start.addingTimeInterval(20)))
        XCTAssertEqual(engine.record.phase, .recording)
    }

    func testOnlyRecordingMotionSamplesEstablishMeasuredCount() throws {
        var record = SessionRecord(startedAt: start)
        record.motionSampleCount = nil
        var engine = SessionEngine(record: record)
        engine.addMotionSample()
        XCTAssertEqual(engine.record.motionSampleCount, 1)
        try engine.pause(at: start.addingTimeInterval(20))
        engine.addMotionSample()
        XCTAssertEqual(engine.record.motionSampleCount, 1)
        try engine.finish(at: start.addingTimeInterval(30))
        engine.addMotionSample()
        XCTAssertEqual(engine.record.motionSampleCount, 1)
    }
}
