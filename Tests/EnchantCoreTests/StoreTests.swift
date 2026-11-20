import XCTest
@testable import EnchantCore
final class StoreTests: XCTestCase {
    var directory: URL!
    override func setUpWithError() throws { directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: directory) }
    func store(_ name: String = "a") throws -> RecordStore { try RecordStore(fileURL: directory.appendingPathComponent(name + ".json"), writerID: name) }
    func record() -> SessionRecord { var r = SessionRecord(startedAt: Date(timeIntervalSince1970: 100)); r.endedAt = Date(timeIntervalSince1970: 130); r.lastCheckpoint = r.endedAt!; r.phase = .finished; return r }
    func testAtomicSaveSurvivesReopening() throws { let a = try store(); try a.upsert(record()); XCTAssertEqual(try store().document.records.count, 1) }
    func testRepeatedImportDoesNotDuplicateRecords() throws { let a = try store(); try a.upsert(record()); let b = try store("b"); XCTAssertTrue(try b.merge(a.export())); XCTAssertFalse(try b.merge(a.export())); XCTAssertEqual(b.document.records.count, 1) }
    func testDeletedRecordCannotReappearAfterStaleOfflineSync() throws {
        let a = try store(); let b = try store("b"); let r = record(); try a.upsert(r); try b.merge(a.export()); let stale = try b.export()
        try a.delete(id: r.id); try a.merge(stale); XCTAssertNotNil(a.document.records.first?.deletedAt)
        try b.merge(a.export()); XCTAssertNotNil(b.document.records.first?.deletedAt)
    }
    func testRestoreIsNewRevisionAndSyncs() throws { let a = try store(); let b = try store("b"); let r = record(); try a.upsert(r); try a.delete(id: r.id); try b.merge(a.export()); try a.restore(id: r.id); try b.merge(a.export()); XCTAssertNil(b.document.records.first?.deletedAt); XCTAssertEqual(b.document.records.first?.revision, 3) }
    func testConcurrentEditsConvergeRegardlessOfDeliveryOrder() throws {
        let a = try store(); let b = try store("b"); let r = record(); try a.upsert(r); try b.merge(a.export())
        var ra = try XCTUnwrap(a.document.records.first); ra.note = "A"; try a.upsert(ra)
        var rb = try XCTUnwrap(b.document.records.first); rb.note = "B"; try b.upsert(rb)
        let da = try a.export(), db = try b.export(); try a.merge(db); try b.merge(da)
        XCTAssertEqual(a.document.records, b.document.records); XCTAssertEqual(a.document.records.first?.note, "B")
    }
    func testCorruptStoreIsNotSilentlyOverwritten() throws { let url = directory.appendingPathComponent("a.json"); try Data("broken".utf8).write(to: url); XCTAssertThrowsError(try store()); XCTAssertEqual(try String(contentsOf: url), "broken") }
    func testInvalidImportIsTransactional() throws { let a = try store(); try a.upsert(record()); let before = a.document; XCTAssertThrowsError(try a.merge(Data("{}".utf8))); XCTAssertEqual(a.document, before) }
    func testFutureSyncVersionIsRejected() throws { let a = try store(); var doc = ArchiveDocument(); doc.schemaVersion = 999; XCTAssertThrowsError(try a.merge(JSONEncoder().encode(doc))); XCTAssertTrue(a.document.records.isEmpty) }
    func testFailedWriteDoesNotChangeMemory() throws { let a = try store(); try a.upsert(record()); let before = a.document; try FileManager.default.removeItem(at: directory); try Data().write(to: directory); XCTAssertThrowsError(try a.upsert(record())); XCTAssertEqual(a.document, before); try FileManager.default.removeItem(at: directory); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
    func testActiveCheckpointIsLocalAndSurvivesReopen() throws { let a = try store(); let r = SessionRecord(startedAt: Date()); try a.checkpoint(r); XCTAssertEqual(try store().document.active?.id, r.id); let b = try store("b"); try b.merge(a.export()); XCTAssertNil(b.document.active) }
    func testImportRejectsInvalidRecordBeforeAnyWrite() throws { let a = try store(); var r = record(); r.endedAt = Date(timeIntervalSince1970: 0); XCTAssertThrowsError(try a.merge(JSONEncoder().encode(ArchiveDocument(records: [r])))); XCTAssertTrue(a.document.records.isEmpty) }
    func testAValidHeartSampleIsRecorded() { var engine = SessionEngine(record: SessionRecord(startedAt: Date(timeIntervalSince1970: 100))); engine.addHeartSample(HeartSample(date: Date(timeIntervalSince1970: 110), bpm: 88, source: "Watch")); XCTAssertEqual(engine.record.averageHeartRate, 88) }
    func testMotionRejectsSingleShakeAndIrregularAlternation() { var detector = MotionDetector(); XCTAssertFalse(detector.consume(acceleration: 1, time: 0)); for i in 1...12 { XCTAssertFalse(detector.consume(acceleration: i % 2 == 0 ? 1 : -1, time: Double(i) * 2)) } }
    func testSustainedMotionCountsOneCyclePerTwoReversals() { var detector = MotionDetector(); var detected = false; for i in 0..<20 { detected = detector.consume(acceleration: i % 2 == 0 ? 0.4 : -0.4, time: Double(i) * 0.4) || detected }; XCTAssertTrue(detected); XCTAssertEqual(detector.cycleCount, 9) }

    func testOfflineMultipleEditsCannotUndoDeletion() throws {
        let a = try store(), b = try store("b"); let r = record(); try a.upsert(r); try b.merge(a.export()); try a.delete(id: r.id)
        var edited = try XCTUnwrap(b.document.records.first); edited.note = "first"; try b.upsert(edited); edited.note = "second"; try b.upsert(edited)
        let da = try a.export(), db = try b.export(); try a.merge(db); try b.merge(da)
        XCTAssertNotNil(a.document.records.first?.deletedAt); XCTAssertEqual(a.document.records, b.document.records)
        try a.restore(id: r.id); try b.merge(a.export()); XCTAssertNil(b.document.records.first?.deletedAt)
    }
    func testExtremeSyncDatesAreRejectedWithoutMutation() throws {
        let a = try store(); var r = record(); r.endedAt = Date(timeIntervalSince1970: 1e20); r.lastCheckpoint = r.endedAt!
        XCTAssertThrowsError(try a.merge(JSONEncoder().encode(ArchiveDocument(records: [r])))); XCTAssertTrue(a.document.records.isEmpty)
        r = record(); r.deletedAt = Date(timeIntervalSince1970: .infinity); XCTAssertThrowsError(try r.validate())
    }
    func testCapacityAcceptsExactByteAndRecordLimits() {
        XCTAssertNoThrow(try RecordStore.validateCapacity(bytes: 30_000_000, records: 50_000))
        XCTAssertNoThrow(try RecordStore.validateCapacity(bytes: 0, records: 0))
    }
    func testCapacityRejectsEachExceededLimitIndependently() {
        XCTAssertThrowsError(try RecordStore.validateCapacity(bytes: 30_000_001, records: 0)) { error in
            switch error as? EnchantError { case .oversizedArchive?: break; default: XCTFail("Expected oversizedArchive") }
        }
        XCTAssertThrowsError(try RecordStore.validateCapacity(bytes: 0, records: 50_001)) { error in
            switch error as? EnchantError { case .oversizedArchive?: break; default: XCTFail("Expected oversizedArchive") }
        }
    }
    func testCompactExportDoesNotInflateSavedArchiveAndPreservesNotes() throws {
        let a = try store(); var r = record(); r.note = "Line 1\nLine 2"; try a.upsert(r)
        let data = try a.export()
        XCTAssertFalse(data.contains(0x0A))
        XCTAssertLessThanOrEqual(data.count, try Data(contentsOf: a.fileURL).count)
        let exported = try JSONDecoder().decode(ArchiveDocument.self, from: data)
        XCTAssertEqual(exported.records.count, 1); XCTAssertEqual(exported.records.first?.note, "Line 1\nLine 2")
        XCTAssertEqual(exported.records.first?.id, r.id); XCTAssertNil(exported.active)
    }
    func testDuplicateStoredUUIDsUseFirstRecordForChangeDetection() throws {
        var older = record(); older.note = "older"; older.revision = 2; older.visibility = VisibilityState()
        var newer = older; newer.note = "newer"; newer.revision = 3
        let incoming = try JSONEncoder().encode(ArchiveDocument(records: [newer]))
        let olderFirstURL = directory.appendingPathComponent("older-first.json")
        try JSONEncoder().encode(ArchiveDocument(records: [older, newer])).write(to: olderFirstURL)
        let olderFirst = try RecordStore(fileURL: olderFirstURL, writerID: "local")
        XCTAssertTrue(try olderFirst.merge(incoming))
        XCTAssertEqual(olderFirst.document.records.count, 1); XCTAssertEqual(olderFirst.document.records.first?.note, "newer")
        XCTAssertFalse(try olderFirst.merge(incoming))

        let newerFirstURL = directory.appendingPathComponent("newer-first.json")
        try JSONEncoder().encode(ArchiveDocument(records: [newer, older])).write(to: newerFirstURL)
        let newerFirst = try RecordStore(fileURL: newerFirstURL, writerID: "local")
        XCTAssertFalse(try newerFirst.merge(incoming))
        XCTAssertEqual(newerFirst.document.records.count, 2)
    }
}
