import Foundation

public enum RecordOrigin: String, Codable, CaseIterable { case manual, automatic, backfill }
public enum SessionPhase: String, Codable { case recording, paused, interrupted, finished }
public struct PauseSpan: Codable, Equatable { public var start: Date; public var end: Date?; public init(start: Date, end: Date? = nil) { self.start = start; self.end = end } }
public struct HeartSample: Codable, Equatable {
    public var date: Date
    public var bpm: Double
    public var source: String
    /// HealthKit container and measurement identity; absent in older archives.
    public var identity: String?
    public init(date: Date, bpm: Double, source: String, identity: String? = nil) {
        self.date = date; self.bpm = bpm; self.source = source; self.identity = identity
    }
}
public struct RecordLink: Codable, Equatable, Identifiable {
    public var id: UUID; public var title: String; public var url: String
    public init(title: String, url: String) throws { let cleaned = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: cleaned), ["http", "https"].contains(components.scheme?.lowercased() ?? ""), let host = components.host, !host.isEmpty, components.user == nil, components.password == nil, components.url != nil else { throw EnchantError.invalidLink }
        id = UUID(); self.title = String(title.prefix(200)); self.url = cleaned }
}
public struct SessionRecord: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var startedAt: Date
    public var endedAt: Date?
    public var timeZoneID: String
    public var origin: RecordOrigin
    public var phase: SessionPhase = .recording
    public var pauses: [PauseSpan] = []
    public var heartSamples: [HeartSample] = []
    public var associatedHealth: [HealthReading]? = []
    public var estimatedCycles: Int = 0
    /// Zero means acquisition has not delivered data; nil preserves legacy archive compatibility.
    public var motionSampleCount: Int?
    public var note: String = ""
    public var links: [RecordLink] = []
    public var revision: Int = 1
    public var writerID: String = ""
    public var modifiedAt: Date
    public var deletedAt: Date?
    public var visibility: VisibilityState?
    public var lastCheckpoint: Date
    public init(startedAt: Date, timeZoneID: String = TimeZone.current.identifier, origin: RecordOrigin = .manual) { self.startedAt = startedAt; self.timeZoneID = timeZoneID; self.origin = origin; self.modifiedAt = startedAt; self.lastCheckpoint = startedAt; self.motionSampleCount = 0 }
    public var cycleEstimate: Int? {
        // Older nonzero estimates remain readable; an unobserved zero is not a measurement.
        if let count = motionSampleCount { return count > 0 ? estimatedCycles : nil }
        return estimatedCycles > 0 ? estimatedCycles : nil
    }
    public func activeDuration(at now: Date) -> TimeInterval {
        let stop = endedAt ?? (phase == .interrupted ? lastCheckpoint : now)
        let paused = pauses.reduce(0.0) { $0 + max(0, min($1.end ?? stop, stop).timeIntervalSince(max($1.start, startedAt))) }
        return max(0, stop.timeIntervalSince(startedAt) - paused)
    }
    public var dayKey: String {
        let formatter = DateFormatter(); formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = TimeZone(identifier: timeZoneID) ?? .gmt; formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: startedAt)
    }
    public var validHeartSamples: [HeartSample] {
        var seen = Set<String>()
        return heartSamples.filter { sample in
            guard sample.bpm.isFinite, (20...300).contains(sample.bpm), sample.date >= startedAt,
                  sample.date <= (endedAt ?? lastCheckpoint),
                  !pauses.contains(where: { sample.date >= $0.start && ($0.end.map { sample.date < $0 } ?? true) }) else { return false }
            let identity = sample.identity ?? "\(sample.date.timeIntervalSinceReferenceDate.bitPattern):\(sample.bpm.bitPattern):\(sample.source)"
            return seen.insert(identity).inserted
        }.sorted { $0.date < $1.date }
    }
    public var peakHeartRate: Double? { validHeartSamples.map(\.bpm).max() }
    public var latestHeartSample: HeartSample? { validHeartSamples.last }
    public var heartSources: [String] { Array(Set(validHeartSamples.map(\.source))).sorted() }
    public var averageHeartRate: Double? {
        let samples = validHeartSamples
        guard !samples.isEmpty else { return nil }
        return samples.reduce(0) { $0 + $1.bpm } / Double(samples.count)
    }
    public var heartSegments: [[HeartSample]] {
        var segments: [[HeartSample]] = []
        for sample in validHeartSamples {
            if let previous = segments.last?.last {
                let crossedPause = pauses.contains { $0.start > previous.date && $0.start <= sample.date }
                if sample.date.timeIntervalSince(previous.date) <= 30 && !crossedPause { segments[segments.count - 1].append(sample); continue }
            }
            segments.append([sample])
        }
        return segments
    }
    public func validate() throws {
        var dates: [Date] = [startedAt, lastCheckpoint, modifiedAt]
        dates.append(contentsOf: [endedAt, deletedAt, visibility?.deletedAt].compactMap { $0 })
        for pause in pauses { dates.append(pause.start); if let end = pause.end { dates.append(end) } }
        dates.append(contentsOf: heartSamples.map(\.date))
        dates.append(contentsOf: (associatedHealth ?? []).map(\.date))
        guard dates.allSatisfy({ $0.timeIntervalSince1970.isFinite && (0...4_102_444_800).contains($0.timeIntervalSince1970) }), (endedAt ?? lastCheckpoint).timeIntervalSince(startedAt) <= 604_800, (visibility?.revision ?? 0) >= 0 else { throw EnchantError.invalidRecord("记录日期或时长超出允许范围。") }

        guard startedAt.timeIntervalSince1970.isFinite, lastCheckpoint >= startedAt, modifiedAt.timeIntervalSince1970.isFinite,
              endedAt == nil || endedAt! >= startedAt, TimeZone(identifier: timeZoneID) != nil,
              revision > 0, estimatedCycles >= 0, (motionSampleCount ?? 0) >= 0, note.count <= 20_000, links.count <= 20, heartSamples.count <= 20_000 else { throw EnchantError.invalidRecord("记录的时间、版本或内容不合法。") }
        var previous = startedAt
        for pause in pauses {
            guard pause.start >= previous, pause.end == nil || pause.end! >= pause.start, pause.start <= (endedAt ?? lastCheckpoint), pause.end == nil || pause.end! <= (endedAt ?? lastCheckpoint) else { throw EnchantError.invalidRecord("暂停区间不合法。") }
            previous = pause.end ?? pause.start
        }
        for link in links { _ = try RecordLink(title: link.title, url: link.url) }
        guard (associatedHealth ?? []).allSatisfy({ $0.value.isFinite && ($0.secondaryValue?.isFinite ?? true) && $0.date.timeIntervalSince1970.isFinite }), (associatedHealth ?? []).count <= 100 else { throw EnchantError.invalidRecord("关联健康记录不合法。") }
        guard heartSamples.allSatisfy({ $0.bpm.isFinite && (20...300).contains($0.bpm) && $0.date >= startedAt && $0.date <= (endedAt ?? lastCheckpoint) }), phase != .finished || endedAt != nil else { throw EnchantError.invalidRecord("采样内容或结束时间不合法。") }
    }
}
public enum EnchantError: Error, LocalizedError {
    case invalidTransition, invalidRecord(String), invalidLink, unsupportedVersion, oversizedArchive
    public var errorDescription: String? {
        switch self {
        case .invalidTransition: return NSLocalizedString("当前记录状态不支持此操作。", comment: "")
        case .invalidRecord(let message):
            // Keep validation messages as stable keys; localize only when presenting the error.
            return Bundle.main.localizedString(forKey: message, value: message, table: "Localizable")
        case .invalidLink: return NSLocalizedString("请输入完整的 http 或 https 链接。", comment: "")
        case .unsupportedVersion: return NSLocalizedString("此记录版本较新，请更新 Enchant 后重试。", comment: "")
        case .oversizedArchive: return NSLocalizedString("记录数据过大，无法接收。", comment: "")
        }
    }
}

public enum HealthMetric: String, Codable, CaseIterable {
    case oxygen, bloodPressure, hrv, respiratoryRate, wristTemperature
    public var title: String { switch self { case .oxygen: return NSLocalizedString("血氧", comment: ""); case .bloodPressure: return NSLocalizedString("血压", comment: ""); case .hrv: return NSLocalizedString("心率变异性", comment: ""); case .respiratoryRate: return NSLocalizedString("呼吸频率", comment: ""); case .wristTemperature: return NSLocalizedString("睡眠腕温", comment: "") } }
    public var unit: String { switch self { case .oxygen: return "%"; case .bloodPressure: return "mmHg"; case .hrv: return "ms"; case .respiratoryRate: return NSLocalizedString("次/分", comment: ""); case .wristTemperature: return "°C" } }
}
public struct HealthReading: Codable, Equatable, Identifiable {
    public var id: UUID
    public var metric: HealthMetric
    public var value: Double
    public var secondaryValue: Double?
    public var date: Date
    public var source: String
    public init(id: UUID = UUID(), metric: HealthMetric, value: Double, secondaryValue: Double? = nil, date: Date, source: String) { self.id = id; self.metric = metric; self.value = value; self.secondaryValue = secondaryValue; self.date = date; self.source = source }
}

/// Deletion/restoration has its own clock; ordinary content edits cannot resurrect a deleted record.
public struct VisibilityState: Codable, Equatable {
    public var revision: Int
    public var writerID: String
    public var deletedAt: Date?
    public init(revision: Int = 0, writerID: String = "", deletedAt: Date? = nil) { self.revision = revision; self.writerID = writerID; self.deletedAt = deletedAt }
}
