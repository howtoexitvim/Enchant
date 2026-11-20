import Foundation

public struct ArchiveDocument: Codable, Equatable {
    public var schemaVersion = 1
    public var records: [SessionRecord] = []
    public var active: SessionRecord?
    public init(records: [SessionRecord] = [], active: SessionRecord? = nil) { self.records = records; self.active = active }
}

/// Mutations commit to disk before changing memory. Call on one serial executor (the app uses MainActor).
public final class RecordStore {
    public private(set) var document: ArchiveDocument
    public let fileURL: URL
    public let writerID: String
    // Reads and writes share these limits so a successful commit can always be reopened.
    static func validateCapacity(bytes: Int, records: Int) throws {
        guard bytes <= 30_000_000, records <= 50_000 else { throw EnchantError.oversizedArchive }
    }
    public init(fileURL: URL, writerID: String) throws {
        self.fileURL = fileURL; self.writerID = writerID
        if FileManager.default.fileExists(atPath: fileURL.path) { document = try Self.decode(Data(contentsOf: fileURL)) }
        else { document = ArchiveDocument() }
    }
    private static func decode(_ data: Data) throws -> ArchiveDocument {
        try validateCapacity(bytes: data.count, records: 0)
        let doc = try JSONDecoder().decode(ArchiveDocument.self, from: data)
        guard doc.schemaVersion == 1 else { throw EnchantError.unsupportedVersion }
        try validateCapacity(bytes: data.count, records: doc.records.count)
        for record in doc.records { try record.validate() }
        if let active = doc.active { try active.validate() }
        return doc
    }
    private func commit(_ next: ArchiveDocument) throws {
        try Self.validateCapacity(bytes: 0, records: next.records.count)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(next)
        try Self.validateCapacity(bytes: data.count, records: next.records.count)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS) || os(watchOS)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: fileURL, options: .atomic)
        #endif
        var protectedURL = fileURL; var values = URLResourceValues(); values.isExcludedFromBackup = true
        try? protectedURL.setResourceValues(values)
        document = next
    }
    public func upsert(_ record: SessionRecord) throws { try saveRecord(record) }
    private func saveRecord(_ record: SessionRecord, visibility: VisibilityState? = nil) throws {
        try record.validate()
        var next = document; var value = record
        let previous = next.records.first { $0.id == value.id }
        guard (previous?.revision ?? 0) < Int.max else { throw EnchantError.invalidRecord("记录版本已达到上限。") }
        value.visibility = visibility ?? previous.map(Self.visibilityState) ?? Self.visibilityState(value)
        value.deletedAt = value.visibility?.deletedAt
        value.revision = (previous?.revision ?? 0) + 1; value.writerID = writerID; value.modifiedAt = Date()
        next.records.removeAll { $0.id == value.id }; next.records.append(value)
        try value.validate()
        if next.active?.id == value.id { next.active = nil }
        try commit(next)
    }
    private static func visibilityState(_ record: SessionRecord) -> VisibilityState { record.visibility ?? VisibilityState(revision: record.deletedAt != nil ? record.revision : 0, writerID: record.writerID, deletedAt: record.deletedAt) }
    private func changeVisibility(id: UUID, deletedAt: Date?) throws {
        guard let value = document.records.first(where: { $0.id == id }) else { return }
        let previous = Self.visibilityState(value)
        guard previous.revision < Int.max else { throw EnchantError.invalidRecord("删除版本已达到上限。") }
        try saveRecord(value, visibility: VisibilityState(revision: previous.revision + 1, writerID: writerID, deletedAt: deletedAt))
    }
    public func delete(id: UUID, at date: Date = Date()) throws { try changeVisibility(id: id, deletedAt: date) }
    public func restore(id: UUID, at date: Date = Date()) throws { try changeVisibility(id: id, deletedAt: nil) }
    public func checkpoint(_ record: SessionRecord?) throws { if let record { try record.validate() }; var next = document; next.active = record; try commit(next) }
    public static func preferred(_ a: SessionRecord, _ b: SessionRecord) -> SessionRecord {
        let av = visibilityState(a), bv = visibilityState(b)
        let visibility: VisibilityState
        if av.revision != bv.revision { visibility = av.revision > bv.revision ? av : bv }
        else if (av.deletedAt != nil) != (bv.deletedAt != nil) { visibility = av.deletedAt != nil ? av : bv }
        else if av.writerID != bv.writerID { visibility = av.writerID > bv.writerID ? av : bv }
        else { visibility = (av.deletedAt ?? .distantPast) >= (bv.deletedAt ?? .distantPast) ? av : bv }
        var winner: SessionRecord
        if a.revision != b.revision { winner = a.revision > b.revision ? a : b }
        else if a.writerID != b.writerID { winner = a.writerID > b.writerID ? a : b }
        else if a.modifiedAt != b.modifiedAt { winner = a.modifiedAt > b.modifiedAt ? a : b }
        else {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let ad = (try? encoder.encode(a)) ?? Data(), bd = (try? encoder.encode(b)) ?? Data()
            winner = ad.lexicographicallyPrecedes(bd) ? b : a
        }
        winner.visibility = visibility; winner.deletedAt = visibility.deletedAt; return winner
    }
    @discardableResult public func merge(_ data: Data) throws -> Bool {
        let incoming = try Self.decode(data)
        var baseline: [UUID: SessionRecord] = [:], values: [UUID: SessionRecord] = [:]
        for r in document.records {
            // Legacy archives may contain duplicate UUIDs; preserve the former first-match comparison.
            if baseline[r.id] == nil { baseline[r.id] = r }
            values[r.id] = values[r.id].map { Self.preferred($0, r) } ?? r
        }
        for r in incoming.records { values[r.id] = values[r.id].map { Self.preferred($0, r) } ?? r }
        guard values.count != baseline.count || values.contains(where: { baseline[$0.key] != $0.value }) else { return false }
        var next = document; next.records = values.values.sorted { $0.id.uuidString < $1.id.uuidString }
        try commit(next); return true
    }
    public func export() throws -> Data {
        // Whitespace must not inflate a valid local archive beyond the receiver's byte limit.
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(ArchiveDocument(records: document.records))
    }
}
