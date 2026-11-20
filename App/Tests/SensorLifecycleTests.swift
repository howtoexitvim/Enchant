import Foundation
import XCTest
@testable import Enchant

@MainActor final class SensorLifecycleTests: XCTestCase {
    func testStartCueIsRequestedBeforeHeartRateCollection() async throws {
        var preferences = AppPreferences(); preferences.healthEnabled = true
        let fixture = try await makeFixture(preferences: preferences)
        defer { fixture.cleanup() }
        fixture.model.start()
        XCTAssertEqual(fixture.model.active?.phase, .recording)
        let relevant = fixture.events.values.filter { $0 == "feedback:start" || $0 == "health:start" }
        XCTAssertEqual(relevant, ["feedback:start", "health:start"])
    }

    func testPausePersistsBeforeStoppingMotionAndResumeKeepsRecordedCycles() async throws {
        let fixture = try await makeFixture()
        defer { fixture.cleanup() }
        fixture.model.start()
        fixture.clock.advance(2)
        fixture.motion.emit(at: fixture.clock.date, cycles: 3)
        var persistedAtStop: SessionPhase?
        fixture.motion.whenStopped = {
            persistedAtStop = (try? RecordStore(fileURL: fixture.model.fileURL, writerID: "pause-check"))?.document.active?.phase
        }
        fixture.clock.advance(8)
        fixture.model.pause()
        XCTAssertEqual(persistedAtStop, .paused)
        XCTAssertEqual(fixture.model.active?.phase, .paused)
        XCTAssertFalse(fixture.motion.isRunning)
        fixture.clock.advance(10)
        fixture.model.resume()
        XCTAssertTrue(fixture.motion.isRunning)
        fixture.clock.advance(1)
        fixture.motion.emit(at: fixture.clock.date, cycles: 2)
        XCTAssertEqual(fixture.model.active?.estimatedCycles, 5)
        XCTAssertEqual(fixture.model.active?.activeDuration(at: fixture.clock.date), 11)
    }

    func testFailedPauseKeepsTheRecordAndMotionRunning() async throws {
        let fixture = try await makeFixture()
        defer { fixture.cleanup() }
        fixture.model.start()
        try fixture.blockArchiveDirectory()
        fixture.clock.advance(10)
        fixture.model.pause()
        XCTAssertNotNil(fixture.model.errorMessage)
        XCTAssertEqual(fixture.model.active?.phase, .recording)
        XCTAssertTrue(fixture.motion.isRunning)
        XCTAssertFalse(fixture.events.values.contains("health:pause"))
    }

    func testUnavailableOrUnobservedMotionDoesNotInventAZeroEstimate() async throws {
        for available in [false, true] {
            let fixture = try await makeFixture(motionAvailable: available)
            defer { fixture.cleanup() }
            fixture.model.start()
            XCTAssertNil(fixture.model.active?.cycleEstimate)
            if available {
                fixture.clock.advance(1)
                fixture.motion.emit(at: fixture.clock.date, cycles: 0, moving: false)
                XCTAssertEqual(fixture.model.active?.cycleEstimate, 0)
                XCTAssertEqual(fixture.model.active?.motionSampleCount, 1)
            }
        }
    }

    func testAutomaticTriggerDoesNotCountTheMonitoringBatchOrStartAnotherSession() async throws {
        var preferences = AppPreferences(); preferences.automaticStart = true
        let fixture = try await makeFixture(preferences: preferences)
        defer { fixture.cleanup() }
        XCTAssertTrue(fixture.model.monitoring)
        fixture.motion.emit(at: fixture.clock.date, candidate: true, cycles: 7)
        let id = try XCTUnwrap(fixture.model.active?.id)
        XCTAssertEqual(fixture.model.active?.origin, .automatic)
        XCTAssertEqual(fixture.model.active?.estimatedCycles, 0)
        XCTAssertNil(fixture.model.active?.cycleEstimate)
        fixture.clock.advance(1)
        fixture.motion.emit(at: fixture.clock.date, candidate: true, cycles: 2)
        XCTAssertEqual(fixture.model.active?.id, id)
        XCTAssertEqual(fixture.model.active?.estimatedCycles, 2)
        XCTAssertEqual(fixture.events.values.filter { $0 == "feedback:start" }.count, 1)
    }

    func testIdleCannotFinishWithoutSamplesOrWithStaleSamples() async throws {
        for previouslySampled in [false, true] {
            var preferences = AppPreferences(); preferences.autoStop = true; preferences.idleSeconds = 1
            let fixture = try await makeFixture(preferences: preferences)
            defer { fixture.cleanup() }
            fixture.model.start()
            if previouslySampled { fixture.motion.emit(at: fixture.clock.date, cycles: 0, moving: false) }
            fixture.clock.advance(20)
            fixture.model.tick(fixture.clock.date)
            XCTAssertEqual(fixture.model.active?.phase, .recording)
            XCTAssertNil(fixture.model.result)
            XCTAssertNil(fixture.model.idleCountdown)
            XCTAssertFalse(fixture.events.values.contains("feedback:finish"))
        }
    }

    func testAutomaticMonitoringFailureDoesNotRestartOnEachSecondTick() async throws {
        var preferences = AppPreferences(); preferences.automaticStart = true
        let fixture = try await makeFixture(preferences: preferences, failMotionStart: true)
        defer { fixture.cleanup() }
        XCTAssertFalse(fixture.model.monitoring)
        for _ in 0..<5 {
            fixture.clock.advance(1)
            fixture.model.tick(fixture.clock.date)
        }
        XCTAssertEqual(fixture.events.values.filter { $0 == "motion:start" }.count, 1)
        XCTAssertNil(fixture.model.active)
    }

    func testLateHealthEventsUseSensorTimestampsForPauseResumeAndInterruption() async throws {
        var preferences = AppPreferences(); preferences.healthEnabled = true
        let fixture = try await makeFixture(preferences: preferences)
        defer { fixture.cleanup() }
        let start = fixture.clock.date
        fixture.model.start()
        fixture.clock.advance(30)
        fixture.model.tick(fixture.clock.date)
        fixture.health.onSessionEvent?(.paused(start.addingTimeInterval(10)))
        XCTAssertEqual(fixture.model.active?.phase, .paused)
        XCTAssertEqual(fixture.model.active?.pauses.first?.start, start.addingTimeInterval(10))
        XCTAssertEqual(fixture.model.active?.activeDuration(at: fixture.clock.date), 10)
        fixture.clock.advance(5)
        fixture.health.onSessionEvent?(.resumed(start.addingTimeInterval(20)))
        XCTAssertEqual(fixture.model.active?.phase, .recording)
        XCTAssertEqual(fixture.model.active?.pauses.first?.end, start.addingTimeInterval(20))
        XCTAssertEqual(fixture.model.active?.activeDuration(at: fixture.clock.date), 25)
        fixture.clock.advance(5)
        fixture.model.tick(fixture.clock.date)
        fixture.health.running = false
        fixture.health.onSessionEvent?(.interrupted(start.addingTimeInterval(25), "system ended the workout"))
        XCTAssertEqual(fixture.model.active?.phase, .interrupted)
        XCTAssertEqual(fixture.model.active?.endedAt, start.addingTimeInterval(25))
        XCTAssertEqual(fixture.model.active?.activeDuration(at: fixture.clock.date), 15)
        XCTAssertFalse(fixture.motion.isRunning)
    }

    func testBackgroundFinishRequestsOneCueOnForegroundReturn() async throws {
        var preferences = AppPreferences(); preferences.healthEnabled = true
        let fixture = try await makeFixture(preferences: preferences)
        defer { fixture.cleanup() }
        fixture.model.preferences.autoSave = false
        fixture.model.start()
        fixture.clock.advance(10)
        fixture.model.sceneChanged(.background)
        fixture.clock.advance(10)
        fixture.model.finish()
        await fixture.model.awaitHealthFinalization()
        XCTAssertEqual(fixture.model.active?.phase, .finished)
        XCTAssertFalse(fixture.events.values.contains("feedback:finish"))
        fixture.model.sceneChanged(.active)
        fixture.model.sceneChanged(.active)
        fixture.model.saveFinished()
        fixture.model.saveFinished()
        XCTAssertEqual(fixture.events.values.filter { $0 == "feedback:finish" }.count, 1)
        XCTAssertEqual(fixture.model.visibleRecords.count, 1)
    }

    func testFailedSaveAndRetryDoNotReplayCompletionFeedback() async throws {
        let fixture = try await makeFixture()
        defer { fixture.cleanup() }
        fixture.model.preferences.autoSave = false
        fixture.model.start()
        fixture.clock.advance(10)
        fixture.model.finish()
        await fixture.model.awaitHealthFinalization()
        try fixture.blockArchiveDirectory()
        fixture.model.saveFinished()
        XCTAssertEqual(fixture.model.active?.phase, .finished)
        XCTAssertNotNil(fixture.model.errorMessage)
        try FileManager.default.removeItem(at: fixture.directory)
        fixture.model.saveFinished()
        XCTAssertNil(fixture.model.active)
        XCTAssertEqual(fixture.model.visibleRecords.count, 1)
        XCTAssertEqual(fixture.events.values.filter { $0 == "feedback:finish" }.count, 1)
    }

    func testCanonicalHeartBackfillIsIdempotentAcrossRepeatedDetailLoads() async throws {
        var preferences = AppPreferences(); preferences.healthEnabled = true
        let fixture = try await makeFixture(preferences: preferences)
        defer { fixture.cleanup() }
        let start = fixture.clock.date
        fixture.model.start()
        fixture.clock.advance(20)
        fixture.model.finish()
        await fixture.model.awaitHealthFinalization()
        fixture.health.querySamples = [
            HeartSample(date: start.addingTimeInterval(5), bpm: 80, source: "Sensor", identity: "container-A:entry-1"),
            HeartSample(date: start.addingTimeInterval(15), bpm: 120, source: "Sensor", identity: "container-A:entry-2")
        ]
        let original = try XCTUnwrap(fixture.model.visibleRecords.first)
        await fixture.model.loadHearts(for: original)
        let first = try XCTUnwrap(fixture.model.visibleRecords.first)
        await fixture.model.loadHearts(for: first)
        let second = try XCTUnwrap(fixture.model.visibleRecords.first)
        XCTAssertEqual(second.heartSamples.count, 2)
        XCTAssertEqual(second.averageHeartRate, 100)
        XCTAssertEqual(second.revision, first.revision)
    }

    func testTransientLiveHeartRateDoesNotEnterTheArchivedSampleSeries() async throws {
        var preferences = AppPreferences(); preferences.healthEnabled = true
        let fixture = try await makeFixture(preferences: preferences)
        defer { fixture.cleanup() }
        fixture.model.start()
        fixture.clock.advance(2)
        let live = HeartSample(date: fixture.clock.date, bpm: 93, source: "live builder statistic")
        fixture.health.onLiveHeartSample?(live)
        XCTAssertEqual(fixture.model.liveHeartSample, live)
        XCTAssertTrue(fixture.model.active?.heartSamples.isEmpty == true)
        fixture.clock.advance(1)
        let canonical = HeartSample(date: fixture.clock.date, bpm: 97, source: "Sensor", identity: "canonical-entry")
        fixture.health.onHeartSample?(canonical)
        fixture.clock.advance(7)
        fixture.model.finish()
        await fixture.model.awaitHealthFinalization()
        let record = try XCTUnwrap(fixture.model.visibleRecords.first)
        XCTAssertEqual(record.heartSamples, [canonical])
        XCTAssertEqual(record.averageHeartRate, 97)
        XCTAssertNil(fixture.model.liveHeartSample)
    }

    func testForegroundReturnCannotEmitCompletionBeforeCollectionEnds() async throws {
        var preferences = AppPreferences(); preferences.healthEnabled = true
        let fixture = try await makeFixture(preferences: preferences)
        defer { fixture.cleanup() }
        fixture.model.start()
        let collectionEnd = SensorGate()
        fixture.health.collectionGate = collectionEnd
        fixture.clock.advance(10)
        fixture.model.finish()
        await collectionEnd.waitUntilEntered()
        fixture.model.sceneChanged(.active)
        XCTAssertNotNil(fixture.model.result)
        XCTAssertFalse(fixture.events.values.contains("feedback:finish"))
        collectionEnd.open()
        await fixture.model.awaitHealthFinalization()
        fixture.model.sceneChanged(.active)
        XCTAssertEqual(fixture.events.values.filter { $0 == "feedback:finish" }.count, 1)
    }

    func testQuickRestartWaitsForPreviousCollectionAndDropsItsOldFinishCue() async throws {
        var preferences = AppPreferences(); preferences.healthEnabled = true
        let fixture = try await makeFixture(preferences: preferences)
        defer { fixture.cleanup() }
        fixture.model.start()
        let oldID = try XCTUnwrap(fixture.model.active?.id)
        let collectionEnd = SensorGate()
        fixture.health.collectionGate = collectionEnd
        fixture.clock.advance(10)
        fixture.model.finish()
        await collectionEnd.waitUntilEntered()
        fixture.model.closeResult()
        fixture.clock.advance(1)
        fixture.model.start()
        XCTAssertNotEqual(fixture.model.active?.id, oldID)
        XCTAssertEqual(fixture.health.startDates.count, 1)
        XCTAssertEqual(fixture.events.values.filter { $0.hasPrefix("feedback:") }, ["feedback:start"])
        collectionEnd.open()
        await fixture.model.awaitHealthFinalization()
        await fixture.model.awaitHealthStart()
        XCTAssertTrue(fixture.health.running)
        XCTAssertEqual(fixture.health.startDates.count, 2)
        let outputs = fixture.events.values.filter { $0.hasPrefix("feedback:") || $0 == "health:start" }
        XCTAssertEqual(outputs, ["feedback:start", "health:start", "feedback:start", "health:start"])
    }

    func testUnsavedFinishedRecordRetainsFinalHeartQueryThroughSaveFailureAndRetry() async throws {
        var preferences = AppPreferences(); preferences.healthEnabled = true
        let fixture = try await makeFixture(preferences: preferences)
        defer { fixture.cleanup() }
        fixture.model.preferences.autoSave = false
        let start = fixture.clock.date
        fixture.model.start()
        fixture.clock.advance(10)
        let sample = HeartSample(date: start.addingTimeInterval(5), bpm: 88, source: "Sensor", identity: "last-container-entry")
        fixture.health.querySamples = [sample]
        fixture.model.finish()
        await fixture.model.awaitHealthFinalization()
        XCTAssertEqual(fixture.model.active?.heartSamples, [sample])
        XCTAssertEqual(fixture.model.result?.heartSamples, [sample])
        try fixture.blockArchiveDirectory()
        fixture.model.saveFinished()
        XCTAssertEqual(fixture.model.active?.heartSamples, [sample])
        try FileManager.default.removeItem(at: fixture.directory)
        fixture.model.saveFinished()
        XCTAssertEqual(fixture.model.visibleRecords.first?.heartSamples, [sample])
        XCTAssertEqual(fixture.events.values.filter { $0 == "feedback:finish" }.count, 1)
    }

    func testEnablingHealthDuringRecordingWaitsForAuthorizationWithoutAnotherStartCue() async throws {
        let fixture = try await makeFixture()
        defer { fixture.cleanup() }
        fixture.model.start()
        let id = try XCTUnwrap(fixture.model.active?.id)
        let authorization = SensorGate()
        fixture.health.authorizationGate = authorization
        fixture.clock.advance(10)
        fixture.model.preferences.healthEnabled = true
        await authorization.waitUntilEntered()
        XCTAssertFalse(fixture.health.running)
        XCTAssertTrue(fixture.health.startDates.isEmpty)
        fixture.clock.advance(5)
        authorization.open()
        await fixture.model.awaitHealthAuthorization()
        await fixture.model.awaitHealthStart()
        XCTAssertEqual(fixture.model.active?.id, id)
        XCTAssertEqual(fixture.model.active?.phase, .recording)
        XCTAssertEqual(fixture.health.startDates, [fixture.clock.date])
        XCTAssertEqual(fixture.events.values.filter { $0 == "feedback:start" }.count, 1)
    }

    func testPauseResumeSupersedesDeferredCollectorStartForTheSameRecord() async throws {
        var preferences = AppPreferences(); preferences.healthEnabled = true
        let fixture = try await makeFixture(preferences: preferences)
        defer { fixture.cleanup() }
        let collectionEnd = SensorGate()
        fixture.health.collectionGate = collectionEnd
        fixture.model.start()
        await collectionEnd.waitUntilEntered()
        let id = try XCTUnwrap(fixture.model.active?.id)
        fixture.clock.advance(10)
        fixture.model.pause()
        fixture.clock.advance(10)
        fixture.model.resume()
        collectionEnd.open()
        await fixture.model.awaitHealthStart()
        XCTAssertEqual(fixture.model.active?.id, id)
        XCTAssertEqual(fixture.model.active?.phase, .recording)
        XCTAssertEqual(fixture.health.startDates, [fixture.clock.date])
        XCTAssertFalse(fixture.events.values.contains("feedback:start"))
    }

    func testResumingInterruptedRecordDuringOrphanRecoveryStartsCollectionAfterCleanup() async throws {
        var preferences = AppPreferences(); preferences.healthEnabled = true
        let time = Date(timeIntervalSince1970: 1_728_403_200)
        var record = SessionRecord(startedAt: time.addingTimeInterval(-20))
        record.lastCheckpoint = time.addingTimeInterval(-10)
        record.modifiedAt = record.lastCheckpoint
        let fixture = try SensorFixture(preferences: preferences, motionAvailable: true, failMotionStart: false,
            recoveredRecord: record, holdRecovery: true)
        defer { fixture.cleanup() }
        let recovery = try XCTUnwrap(fixture.health.recoveryGate)
        await recovery.waitUntilEntered()
        fixture.model.sceneChanged(.active)
        fixture.model.resume()
        XCTAssertEqual(fixture.model.active?.phase, .recording)
        XCTAssertTrue(fixture.health.startDates.isEmpty)
        XCTAssertFalse(fixture.health.running)
        recovery.open()
        await fixture.model.awaitHealthRecovery()
        await fixture.model.awaitHealthAuthorization()
        await fixture.model.awaitHealthStart()
        XCTAssertEqual(fixture.model.active?.id, record.id)
        XCTAssertTrue(fixture.health.running)
        XCTAssertEqual(fixture.health.startDates, [time])
        XCTAssertFalse(fixture.events.values.contains("feedback:start"))
    }

    func testCurrentHeartRateUsesNewestReadingAndDelayedLiveDataCannotRegressIt() async throws {
        var preferences = AppPreferences(); preferences.healthEnabled = true
        let fixture = try await makeFixture(preferences: preferences)
        defer { fixture.cleanup() }
        fixture.model.start()
        let start = fixture.clock.date
        fixture.health.onLiveHeartSample?(HeartSample(date: start, bpm: 80, source: "live statistic"))
        fixture.clock.advance(31)
        fixture.health.onHeartSample?(HeartSample(date: fixture.clock.date, bpm: 91, source: "Sensor", identity: "newer-canonical"))
        fixture.clock.advance(1)
        XCTAssertEqual(fixture.model.currentHeartRate(for: try XCTUnwrap(fixture.model.active)), 91)
        fixture.health.onLiveHeartSample?(HeartSample(date: fixture.clock.date, bpm: 97, source: "live statistic"))
        fixture.health.onLiveHeartSample?(HeartSample(date: start.addingTimeInterval(25), bpm: 75, source: "delayed live statistic"))
        XCTAssertEqual(fixture.model.currentHeartRate(for: try XCTUnwrap(fixture.model.active)), 97)
    }

    private func makeFixture(preferences: AppPreferences = AppPreferences(), motionAvailable: Bool = true, failMotionStart: Bool = false) async throws -> SensorFixture {
        let fixture = try SensorFixture(preferences: preferences, motionAvailable: motionAvailable, failMotionStart: failMotionStart)
        await fixture.model.awaitHealthRecovery()
        fixture.model.sceneChanged(.active)
        await fixture.model.awaitHealthAuthorization()
        return fixture
    }
}

@MainActor private final class SensorClock {
    var date = Date(timeIntervalSince1970: 1_728_403_200)
    func advance(_ seconds: TimeInterval) { date = date.addingTimeInterval(seconds) }
}

@MainActor private final class SensorEvents { var values: [String] = [] }

/// A controlled external operation: tests release it explicitly instead of sleeping or polling.
@MainActor private final class SensorGate {
    private(set) var isOpen = false
    private var entered = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var observers: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        entered = true
        let ready = observers; observers.removeAll()
        ready.forEach { $0.resume() }
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { observers.append($0) }
    }
    func open() {
        isOpen = true
        let ready = waiters; waiters.removeAll()
        ready.forEach { $0.resume() }
    }
}

@MainActor private final class SensorFixture {
    let model: AppModel
    let directory: URL
    let defaultsName: String
    let clock: SensorClock
    let events: SensorEvents
    let motion: LifecycleMotion
    let health: LifecycleHealth
    init(preferences: AppPreferences, motionAvailable: Bool, failMotionStart: Bool, recoveredRecord: SessionRecord? = nil, holdRecovery: Bool = false) throws {
        let name = "enchant.sensor-lifecycle.\(UUID().uuidString)"
        defaultsName = name
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let defaults = UserDefaults(suiteName: name)!
        defaults.set(try JSONEncoder().encode(preferences), forKey: "preferences")
        let controlledClock = SensorClock(), observedEvents = SensorEvents()
        clock = controlledClock; events = observedEvents
        let controlledMotion = LifecycleMotion(events: observedEvents)
        controlledMotion.available = motionAvailable; controlledMotion.failStart = failMotionStart
        motion = controlledMotion
        let controlledHealth = LifecycleHealth(events: observedEvents)
        if holdRecovery { controlledHealth.recoveryGate = SensorGate() }
        health = controlledHealth
        let archiveURL = directory.appendingPathComponent("archive.json")
        if let recoveredRecord { try RecordStore(fileURL: archiveURL, writerID: "recovery-fixture").checkpoint(recoveredRecord) }
        model = AppModel(fileURL: archiveURL, defaults: defaults, syncEnabled: false,
            motion: controlledMotion, health: controlledHealth,
            feedbackOutput: { plan in observedEvents.values.append("feedback:\(plan.cue.rawValue)"); return true },
            recordsMotion: true, clock: { controlledClock.date })
    }
    func blockArchiveDirectory() throws {
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        try Data().write(to: directory)
    }
    func cleanup() {
        motion.whenStopped = nil
        health.collectionGate?.open(); health.authorizationGate?.open(); health.recoveryGate?.open()
        try? FileManager.default.removeItem(at: directory)
        UserDefaults().removePersistentDomain(forName: defaultsName)
    }
}

@MainActor private final class LifecycleMotion: MotionCapturing {
    let events: SensorEvents
    var available = true
    var isRunning = false
    var failStart = false
    var whenStopped: (() -> Void)?
    var onUpdate: ((Bool, Int) -> Void)?
    var onSample: (() -> Void)?
    var onActivity: (() -> Void)?
    var onFailure: ((String) -> Void)?
    private var lastSample: Date?
    init(events: SensorEvents) { self.events = events }
    func start(threshold: Double) {
        events.values.append("motion:start")
        lastSample = nil
        isRunning = available && !failStart
        if !isRunning { onFailure?("motion could not start") }
    }
    func stop() { isRunning = false; lastSample = nil; events.values.append("motion:stop"); whenStopped?() }
    func hasFreshSamples(at date: Date) -> Bool {
        guard isRunning, let lastSample else { return false }
        return (0...5).contains(date.timeIntervalSince(lastSample))
    }
    func checkSampling(at date: Date) {}
    func emit(at date: Date, candidate: Bool = false, cycles: Int, moving: Bool = true) {
        guard isRunning else { return }
        lastSample = date
        onSample?()
        if moving { onActivity?() }
        onUpdate?(candidate, cycles)
    }
}

@MainActor private final class LifecycleHealth: HealthCollecting {
    let events: SensorEvents
    var status = "test sensor"
    var running = false
    var available = true
    var recoveryInProgress = false
    var collectionCleanupPending: Bool { collectionGate.map { !$0.isOpen } ?? false }
    var collectionGate: SensorGate?
    var authorizationGate: SensorGate?
    var recoveryGate: SensorGate?
    var onHeartSample: ((HeartSample) -> Void)?
    var onLiveHeartSample: ((HeartSample) -> Void)?
    var onSessionEvent: ((HealthSessionEvent) -> Void)?
    var querySamples: [HeartSample] = []
    var startDates: [Date] = []
    init(events: SensorEvents) { self.events = events }
    func authorize() async { if let authorizationGate { await authorizationGate.wait() } }
    func start(at date: Date) {
        guard available, !recoveryInProgress, !collectionCleanupPending else { return }
        running = true; startDates.append(date); events.values.append("health:start")
    }
    func pause() { events.values.append("health:pause") }
    func resume() { running = true; events.values.append("health:resume") }
    func stop(writeWorkout: Bool) { running = false; events.values.append("health:stop") }
    func heartSamples(start: Date, end: Date) async throws -> [HeartSample] { querySamples }
    func cleanupRecoveredWorkout() async {
        recoveryInProgress = true
        if let recoveryGate { await recoveryGate.wait() }
        recoveryInProgress = false
    }
    func waitForCollectionEnd() async { if let collectionGate { await collectionGate.wait() } }
}
