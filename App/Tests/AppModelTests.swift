import XCTest
@testable import Enchant
@MainActor final class AppModelTests: XCTestCase {
    func makeModel() -> (AppModel, URL, String) {
        let name = "enchant.unit.\(UUID().uuidString)"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let model = AppModel(fileURL: directory.appendingPathComponent("archive.json"), defaults: UserDefaults(suiteName: name)!, syncEnabled: false)
        return (model, directory, name)
    }
    func testFailedPauseRemainsRecording() throws {
        let (model, directory, name) = makeModel(); defer { try? FileManager.default.removeItem(at: directory); UserDefaults().removePersistentDomain(forName: name) }
        model.start(); XCTAssertEqual(model.active?.phase, .recording)
        try FileManager.default.removeItem(at: directory); try Data().write(to: directory)
        model.pause(); XCTAssertEqual(model.active?.phase, .recording); XCTAssertNotNil(model.errorMessage)
    }
    func testHealthInterruptionPreservesInterruptedCheckpoint() {
        let (model, directory, name) = makeModel(); defer { try? FileManager.default.removeItem(at: directory); UserDefaults().removePersistentDomain(forName: name) }
        model.start(); model.health.onSessionEvent?(.interrupted(model.active!.lastCheckpoint, "HealthKit ended the runtime"))
        XCTAssertEqual(model.active?.phase, .interrupted); XCTAssertFalse(model.monitoring)
        XCTAssertEqual(model.active?.activeDuration(at: Date().addingTimeInterval(3600)), 0)
    }
    func testFailedSaveRetainsFinishedRecordForRetry() throws {
        let (model, directory, name) = makeModel(); defer { try? FileManager.default.removeItem(at: directory); UserDefaults().removePersistentDomain(forName: name) }
        model.preferences.autoSave = false; model.start(); model.finish(); XCTAssertEqual(model.active?.phase, .finished)
        try FileManager.default.removeItem(at: directory); try Data().write(to: directory)
        model.saveFinished(); XCTAssertEqual(model.active?.phase, .finished); XCTAssertTrue(model.records.isEmpty)
        try FileManager.default.removeItem(at: directory); model.saveFinished(); XCTAssertNil(model.active); XCTAssertEqual(model.visibleRecords.count, 1)
    }
    func testFailedDiscardKeepsPendingResultAndAllowsRetry() throws {
        let (model, directory, name) = makeModel(); defer { try? FileManager.default.removeItem(at: directory); UserDefaults().removePersistentDomain(forName: name) }
        model.preferences.autoSave = false; model.start(); model.finish()
        let id = try XCTUnwrap(model.result?.id)
        try FileManager.default.removeItem(at: directory); try Data().write(to: directory)
        XCTAssertFalse(model.discardActive())
        XCTAssertEqual(model.result?.id, id); XCTAssertEqual(model.active?.phase, .finished)
        model.closeResult(); XCTAssertEqual(model.result?.id, id)
        try FileManager.default.removeItem(at: directory)
        model.saveFinished(); XCTAssertNil(model.active); XCTAssertEqual(model.visibleRecords.first?.id, id)
    }
    func testDisablingHealthInBackgroundInterruptsAndStopsElapsedTime() throws {
        let (model, directory, name) = makeModel(); defer { try? FileManager.default.removeItem(at: directory); UserDefaults().removePersistentDomain(forName: name) }
        model.sceneChanged(.background); model.preferences.healthEnabled = true; model.start(); model.preferences.healthEnabled = false
        XCTAssertEqual(model.active?.phase, .interrupted)
        let record = try XCTUnwrap(model.active)
        XCTAssertEqual(record.activeDuration(at: Date()), record.activeDuration(at: Date().addingTimeInterval(3600)), accuracy: 0.001)
    }
    func testFailedDeleteRetainsVisibleRecordForRetry() throws {
        let (model, directory, name) = makeModel(); defer { try? FileManager.default.removeItem(at: directory); UserDefaults().removePersistentDomain(forName: name) }
        model.start(); model.finish(); let id = try XCTUnwrap(model.visibleRecords.first?.id)
        try FileManager.default.removeItem(at: directory); try Data().write(to: directory)
        XCTAssertFalse(model.delete(id)); XCTAssertEqual(model.visibleRecords.first?.id, id)
        try FileManager.default.removeItem(at: directory)
        XCTAssertTrue(model.delete(id)); XCTAssertTrue(model.visibleRecords.isEmpty); XCTAssertEqual(model.deletedRecords.first?.id, id)
    }
    func testInlineLinksOnlyAcceptHTTPAndPreserveLegacyNotes() throws {
        let text = "A note https://example.com/path http://example.org https://example.com/path mailto:user@example.com"
        let links = RecordLink.detected(in: text)
        XCTAssertEqual(links.map(\.url), ["https://example.com/path", "http://example.org"])
        var record = SessionRecord(startedAt: Date()); record.note = "old note"; record.links = [try RecordLink(title: "Example", url: "https://example.com")]
        XCTAssertEqual(record.journalText, "old note\n\nExample\nhttps://example.com")
        record.note = "https://example.com"; XCTAssertEqual(record.journalText, "https://example.com")
    }
    func testOlderPreferencesKeepDefaultAutomaticStart() throws {
        let data = Data("{\"sound\":false,\"haptics\":true}".utf8)
        let prefs = try JSONDecoder().decode(AppPreferences.self, from: data)
        XCTAssertFalse(prefs.automaticStart); XCTAssertFalse(prefs.sound); XCTAssertTrue(prefs.haptics)
    }
    func testAggregateDurationDoesNotStopAtSevenDays() {
        XCTAssertEqual(SessionRecord.durationString(8 * 24 * 3600), "192:00:00")
        XCTAssertEqual(SessionRecord.durationString(.infinity), "--")
    }

    func testPairedArchiveRoundTripKeepsNotesDeletionAndRestore() throws {
        let (watch, watchDirectory, watchName) = makeModel()
        let (phone, phoneDirectory, phoneName) = makeModel()
        defer { for directory in [watchDirectory, phoneDirectory] { try? FileManager.default.removeItem(at: directory) }; for name in [watchName, phoneName] { UserDefaults().removePersistentDomain(forName: name) } }
        func archive(_ model: AppModel) throws -> Data { try RecordStore(fileURL: model.fileURL, writerID: "test-read").export() }
        watch.start(); watch.finish()
        let id = try XCTUnwrap(watch.visibleRecords.first?.id)
        XCTAssertTrue(phone.receiveArchive(try archive(watch)))
        XCTAssertTrue(phone.receiveArchive(try archive(watch)))
        XCTAssertEqual(phone.visibleRecords.count, 1)
        var record = try XCTUnwrap(phone.visibleRecords.first)
        record.note = "修改后收藏 https://example.com"
        XCTAssertTrue(phone.save(record))
        XCTAssertTrue(watch.receiveArchive(try archive(phone)))
        XCTAssertEqual(watch.visibleRecords.first?.note, record.note)
        XCTAssertTrue(watch.delete(id)); XCTAssertTrue(phone.receiveArchive(try archive(watch)))
        XCTAssertTrue(phone.visibleRecords.isEmpty); XCTAssertEqual(phone.deletedRecords.first?.id, id)
        phone.restore(id); XCTAssertTrue(watch.receiveArchive(try archive(phone)))
        XCTAssertEqual(watch.visibleRecords.first?.id, id); XCTAssertEqual(watch.visibleRecords.first?.note, record.note)
    }

    func testReceiverPermanentlyHandlesMalformedDataButRetriesWriteFailure() throws {
        let (source, sourceDirectory, sourceName) = makeModel()
        let (target, targetDirectory, targetName) = makeModel()
        defer { for directory in [sourceDirectory, targetDirectory] { try? FileManager.default.removeItem(at: directory) }; for name in [sourceName, targetName] { UserDefaults().removePersistentDomain(forName: name) } }
        XCTAssertTrue(target.receiveArchive(Data("invalid JSON".utf8)))
        XCTAssertNotNil(target.errorMessage); XCTAssertTrue(target.records.isEmpty)
        source.start(); source.finish()
        let data = try RecordStore(fileURL: source.fileURL, writerID: "test-read").export()
        if FileManager.default.fileExists(atPath: targetDirectory.path) { try FileManager.default.removeItem(at: targetDirectory) }; try Data().write(to: targetDirectory)
        XCTAssertFalse(target.receiveArchive(data)); XCTAssertTrue(target.records.isEmpty)
        try FileManager.default.removeItem(at: targetDirectory)
        XCTAssertTrue(target.receiveArchive(data)); XCTAssertEqual(target.visibleRecords.count, 1)
    }

    func testDamagedArchiveCanBePreservedAndReplacedWithoutLosingOriginal() throws {
        let name = "enchant.recovery.\(UUID().uuidString)"
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        defer { try? FileManager.default.removeItem(at: directory); UserDefaults().removePersistentDomain(forName: name) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("archive.json")
        let original = Data("unreadable original archive".utf8); try original.write(to: url)
        let model = AppModel(fileURL: url, defaults: UserDefaults(suiteName: name)!, syncEnabled: false)
        XCTAssertNotNil(model.loadError); XCTAssertEqual(try Data(contentsOf: url), original)
        model.createFreshStorePreservingOriginal(); XCTAssertNil(model.loadError)
        let preserved = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix("archive-damaged-") })
        XCTAssertEqual(try Data(contentsOf: preserved), original)
        model.start(); model.finish(); XCTAssertEqual(model.visibleRecords.count, 1)
        XCTAssertEqual(try RecordStore(fileURL: url, writerID: "reopen").document.records.count, 1)
    }

}
