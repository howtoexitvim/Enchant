import Foundation

public struct SessionEngine {
    public private(set) var record: SessionRecord
    private var heartIdentities: Set<String>
    public init(record: SessionRecord) { self.record = record; heartIdentities = Set(record.heartSamples.map(Self.heartKey)) }
    private static func heartKey(_ sample: HeartSample) -> String {
        sample.identity.map { "id:\($0)" } ?? "legacy:\(sample.date.timeIntervalSinceReferenceDate.bitPattern):\(sample.bpm.bitPattern):\(sample.source)"
    }
    private func checkTime(_ date: Date) throws { guard date >= record.lastCheckpoint else { throw EnchantError.invalidTransition } }
    public mutating func pause(at date: Date) throws {
        guard record.phase == .recording else { throw EnchantError.invalidTransition }; try checkTime(date)
        record.pauses.append(PauseSpan(start: date)); record.phase = .paused; checkpoint(at: date)
    }
    public mutating func resume(at date: Date) throws {
        guard record.phase == .paused || record.phase == .interrupted else { throw EnchantError.invalidTransition }; try checkTime(date)
        if record.pauses.last?.end == nil, !record.pauses.isEmpty { record.pauses[record.pauses.count - 1].end = date }
        else if record.phase == .interrupted { record.pauses.append(PauseSpan(start: record.lastCheckpoint, end: date)) }
        record.phase = .recording; record.endedAt = nil; checkpoint(at: date)
    }
    public mutating func finish(at date: Date) throws {
        guard record.phase != .finished else { throw EnchantError.invalidTransition }; try checkTime(date)
        let end = record.phase == .interrupted ? record.lastCheckpoint : date
        if !record.pauses.isEmpty, record.pauses.last?.end == nil { record.pauses[record.pauses.count - 1].end = end }
        record.endedAt = end; record.phase = .finished; record.lastCheckpoint = end; record.modifiedAt = date
    }
    public mutating func checkpoint(at date: Date) { guard record.phase == .recording || record.phase == .paused else { return }; record.lastCheckpoint = max(date, record.lastCheckpoint); record.modifiedAt = record.lastCheckpoint }
    public mutating func recover() { guard record.phase != .finished else { return }; record.phase = .interrupted; record.endedAt = record.lastCheckpoint }
    public mutating func systemPause(at date: Date) {
        guard record.phase == .recording, date >= record.startedAt,
              date >= (record.pauses.last?.end ?? record.startedAt) else { return }
        record.pauses.append(PauseSpan(start: date)); record.phase = .paused; checkpoint(at: date)
    }
    public mutating func systemResume(at date: Date) {
        guard record.phase == .paused, let pause = record.pauses.last, pause.end == nil, date >= pause.start else { return }
        record.pauses[record.pauses.count - 1].end = date
        record.phase = .recording; record.endedAt = nil; checkpoint(at: date)
    }
    public mutating func interrupt(at date: Date) {
        guard record.phase != .finished, date >= record.startedAt else { return }
        record.pauses = record.pauses.filter { $0.start < date }.map { pause in
            var value = pause
            if let end = value.end, end > date { value.end = date }
            return value
        }
        record.heartSamples.removeAll { $0.date > date }
        record.lastCheckpoint = date; record.endedAt = date; record.phase = .interrupted
        record.modifiedAt = max(record.modifiedAt, date)
    }
    public mutating func addHeartSample(_ sample: HeartSample) {
        guard record.phase == .recording || record.phase == .paused,
              sample.bpm.isFinite, (20...300).contains(sample.bpm), sample.date >= record.startedAt,
              !record.pauses.contains(where: { sample.date >= $0.start && ($0.end == nil || sample.date < $0.end!) }),
              record.heartSamples.count < 20_000, heartIdentities.insert(Self.heartKey(sample)).inserted else { return }
        record.heartSamples.append(sample); checkpoint(at: sample.date)
    }
    public mutating func addMotionSample() {
        guard record.phase == .recording else { return }
        record.motionSampleCount = min(record.motionSampleCount ?? 0, Int.max - 1) + 1
    }
    public mutating func addCycle() { if record.phase == .recording { record.estimatedCycles += 1 } }
}
