import Foundation
import SwiftUI
import Combine

@MainActor final class AppModel: ObservableObject {
    @Published private(set) var records: [SessionRecord] = []
    @Published private(set) var engine: SessionEngine?
    @Published var result: SessionRecord?
    @Published var errorMessage: String?
    @Published var loadError: String?
    @Published var monitoring = false
    @Published var motionStatus = L10n.text("动作采集未开启")
    @Published var idleCountdown: Int?
    @Published var now = Date()
    @Published private(set) var liveHeartSample: HeartSample?
    @Published var preferences: AppPreferences {
        didSet {
            if let data = try? JSONEncoder().encode(preferences) { defaults.set(data, forKey: "preferences") }
            if oldValue.healthEnabled && !preferences.healthEnabled {
                invalidateHealthStart(); health.stop(writeWorkout: false); healthAuthorizationPending = false; liveHeartSample = nil
                if !foregroundActive, var interrupted = engine, interrupted.record.phase == .recording {
                    interrupted.checkpoint(at: clock()); interrupted.recover(); engine = interrupted
                    motion.stop(); monitoring = false; idleCountdown = nil; persistCheckpoint()
                }
            }
            if !oldValue.healthEnabled && preferences.healthEnabled { healthAuthorizationPending = true; authorizeHealthIfNeeded() }
            if !preferences.autoStop { idleCountdown = nil }
            if oldValue.automaticStart != preferences.automaticStart { updateMonitoring() }
            if !applyingRemotePreferences {
                preferenceRevision = min(preferenceRevision, Int.max - 1) + 1
                preferenceWriter = writerID; persistPreferenceStamp(); syncPreferences()
            }
        }
    }
    let health: any HealthCollecting
    let connectivity: ConnectivityService
    let fileURL: URL
    private let motion: any MotionCapturing
    private let feedbackOutput: (FeedbackPlan) -> Bool
    private var feedbackPolicy = FeedbackPolicy()
    private let recordsMotion: Bool
    private let clock: () -> Date
    private let defaults: UserDefaults
    private var store: RecordStore?
    private var timer: AnyCancellable?
    private var lastPersist = Date.distantPast
    private var lastMovement = Date()
    private var cooldownUntil = Date.distantPast
    private var writerID: String
    private var preferenceRevision = 1
    private var preferenceWriter = ""
    private var applyingRemotePreferences = false
    private var foregroundActive = false
    private var healthAuthorizationPending = false
    private var healthRecoveryTask: Task<Void, Never>?
    private var healthStartTask: Task<Void, Never>?
    private var healthAuthorizationTask: Task<Void, Never>?
    private var healthStartGeneration = 0
    private var healthAuthorizing = false
    private var healthFinalizationTask: Task<Void, Never>?
    private var healthRecoveryPending = false
    private var motionRetryAfter = Date.distantPast
    var active: SessionRecord? { engine?.record }
    var visibleRecords: [SessionRecord] { records.filter { $0.deletedAt == nil }.sorted { $0.startedAt > $1.startedAt } }
    var deletedRecords: [SessionRecord] { records.filter { $0.deletedAt != nil }.sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) } }
    init(fileURL suppliedFileURL: URL? = nil, defaults suppliedDefaults: UserDefaults? = nil, syncEnabled: Bool = true,
         motion suppliedMotion: (any MotionCapturing)? = nil, health suppliedHealth: (any HealthCollecting)? = nil,
         feedbackOutput suppliedFeedback: ((FeedbackPlan) -> Bool)? = nil, recordsMotion suppliedRole: Bool? = nil,
         clock: @escaping () -> Date = Date.init) {
        self.clock = clock
        motion = suppliedMotion ?? MotionService()
        health = suppliedHealth ?? HealthService()
        let feedbackService = FeedbackService()
        feedbackOutput = suppliedFeedback ?? { feedbackService.play($0) }
        #if os(watchOS)
        recordsMotion = suppliedRole ?? true
        #else
        recordsMotion = suppliedRole ?? false
        #endif
        now = clock(); lastMovement = clock()
        var testing = false, demo = false, keep = false
        #if DEBUG
        testing = ProcessInfo.processInfo.arguments.contains("-ui-testing")
        demo = ProcessInfo.processInfo.arguments.contains("-demo")
        keep = ProcessInfo.processInfo.arguments.contains("-keep-data")
        #endif
        defaults = suppliedDefaults ?? ((testing || demo) ? UserDefaults(suiteName: "enchant.preview")! : .standard)
        if testing && !keep { defaults.removePersistentDomain(forName: "enchant.preview") }
        var loadedPreferences = (defaults.data(forKey: "preferences").flatMap { try? JSONDecoder().decode(AppPreferences.self, from: $0) }) ?? AppPreferences()
        loadedPreferences.autoSave = true; loadedPreferences.writeWorkout = false
        preferences = loadedPreferences
        writerID = defaults.string(forKey: "writerID") ?? UUID().uuidString; defaults.set(writerID, forKey: "writerID")
        preferenceRevision = max(1, defaults.integer(forKey: "preferenceRevision")); preferenceWriter = defaults.string(forKey: "preferenceWriter") ?? writerID
        #if DEBUG
        let directoryName = testing ? "EnchantUITest" : demo ? "EnchantDemo" : "Enchant"
        #else
        let directoryName = "Enchant"
        #endif
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(directoryName)
        fileURL = suppliedFileURL ?? directory.appendingPathComponent("archive-v1.json")
        if testing && !keep { try? FileManager.default.removeItem(at: directory) }
        connectivity = ConnectivityService(enabled: syncEnabled && !testing && !demo, directory: fileURL.deletingLastPathComponent().appendingPathComponent("Sync"))
        do {
            let s = try RecordStore(fileURL: fileURL, writerID: writerID); store = s; records = s.document.records
            if let record = s.document.active {
                var recovered = SessionEngine(record: record)
                if record.phase == .finished { result = record } else { recovered.recover() }
                engine = recovered; try s.checkpoint(recovered.record)
            }
            #if DEBUG
            if demo && records.isEmpty { try seedDemo() }
            #endif
        } catch { loadError = L10n.format("本地资料库无法读取，原文件已保留。%@", error.localizedDescription) }
        motion.onFailure = { [weak self] message in
            guard let self else { return }
            self.motionStatus = message; self.monitoring = false; self.idleCountdown = nil
            // A failed sensor must not be restarted by every one-second UI tick.
            self.motionRetryAfter = self.clock().addingTimeInterval(15)
        }
        motion.onSample = { [weak self] in self?.engine?.addMotionSample() }
        motion.onActivity = { [weak self] in
            guard let self, self.active?.phase == .recording else { return }
            self.lastMovement = self.clock(); if self.idleCountdown != nil { self.idleCountdown = nil }
        }
        motion.onUpdate = { [weak self] candidate, cycles in
            guard let self else { return }
            if self.monitoring && candidate && self.clock() >= self.cooldownUntil {
                self.start(origin: .automatic)
                // The monitoring burst belongs before the new session's start time.
                return
            }
            if self.active?.phase == .recording, cycles > 0 {
                for _ in 0..<min(cycles, 100) { self.engine?.addCycle() }
            }
        }
        health.onHeartSample = { [weak self] sample in
            guard let self, self.preferences.healthEnabled, sample.date <= self.clock() else { return }
            self.engine?.addHeartSample(sample)
        }
        health.onLiveHeartSample = { [weak self] sample in
            guard let self, self.preferences.healthEnabled, let record = self.active, record.phase == .recording,
                  sample.bpm.isFinite, (20...300).contains(sample.bpm), sample.date >= record.startedAt,
                  sample.date <= self.clock(), sample.date >= (self.liveHeartSample?.date ?? .distantPast), !record.pauses.contains(where: {
                      sample.date >= $0.start && ($0.end.map { sample.date < $0 } ?? true)
                  }) else { return }
            // Builder statistics provide a current reading, not an additional archived measurement.
            self.liveHeartSample = sample
        }
        health.onSessionEvent = { [weak self] event in self?.handleHealthEvent(event) }
        connectivity.onReceive = { [weak self] data in self?.receiveArchive(data) ?? false }
        connectivity.onPreferences = { [weak self] data in self?.receivePreferences(data) }
        connectivity.onReady = { [weak self] in self?.sync(); self?.syncPreferences() }
        connectivity.refresh()
        healthAuthorizationPending = preferences.healthEnabled
        if recordsMotion { recoverHealthSession() }
        timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            guard let self else { return }; self.tick(self.clock())
        }
    }
    func start(origin: RecordOrigin = .manual) {
        guard engine == nil, loadError == nil, !healthRecoveryPending else { return }
        let date = clock(); var record = SessionRecord(startedAt: date, origin: origin); record.writerID = writerID
        do {
            try requireStore().checkpoint(record); engine = SessionEngine(record: record); now = date; monitoring = false; lastMovement = date; idleCountdown = nil
            if recordsMotion {
                startMotion()
            } else { motionStatus = L10n.text("iPhone 记时 · 动作采集请使用 Watch") }
            liveHeartSample = nil
            startHealthAndFeedback(for: record.id, at: date)
        } catch { errorMessage = error.localizedDescription }
    }
    func pause() {
        guard mutate({ try $0.pause(at: clock()) }) else { return }
        invalidateHealthStart(); motion.stop(); health.pause(); liveHeartSample = nil; idleCountdown = nil
    }
    func resume() {
        let needsNewCollection = active?.phase == .interrupted || !health.running
        guard mutate({ try $0.resume(at: clock()) }), let record = active else { return }
        lastMovement = clock(); liveHeartSample = nil; idleCountdown = nil
        if needsNewCollection { startHealthAndFeedback(for: record.id, at: clock(), cue: false) }
        else { health.resume() }
        if recordsMotion { startMotion() }
    }
    func finish() {
        guard var value = engine, value.record.phase != .finished else { return }
        do {
            try value.finish(at: clock()); try requireStore().checkpoint(value.record); engine = value
            invalidateHealthStart(); motion.stop(); monitoring = false; idleCountdown = nil; liveHeartSample = nil; health.stop(writeWorkout: preferences.writeWorkout)
            result = value.record; cooldownUntil = clock().addingTimeInterval(8)
            if preferences.autoSave { saveFinished() }
            // Flush collection before haptics: Watch haptics temporarily interrupt heart-rate sampling.
            _ = feedbackPolicy.request(.finish, isForeground: false, sound: preferences.sound, haptics: preferences.haptics)
            finalizeHealth(for: value.record)
        } catch { errorMessage = error.localizedDescription }
    }
    func saveFinished() {
        guard let value = engine?.record, value.phase == .finished else { return }
        do { try requireStore().upsert(value); records = store!.document.records; engine = nil; sync()
            if let finished = records.first(where: { $0.id == value.id }) { result = finished } }
        catch { errorMessage = L10n.format("保存失败，记录已保留在待保存结果中：%@", error.localizedDescription) }
    }
    @discardableResult func discardActive() -> Bool {
        do { try requireStore().checkpoint(nil); engine = nil; result = nil; liveHeartSample = nil; invalidateHealthStart(); motion.stop(); health.stop(writeWorkout: false); monitoring = false; idleCountdown = nil; cooldownUntil = clock().addingTimeInterval(8); return true }
        catch { errorMessage = error.localizedDescription; return false }
    }
    private func updateMonitoring() {
        guard recordsMotion else { return }
        guard engine == nil, result == nil, !healthRecoveryPending, clock() >= motionRetryAfter else { return }
        if !preferences.automaticStart || !foregroundActive { monitoring = false; motion.stop(); return }
        guard motion.available else { monitoring = false; motionStatus = L10n.text("动作不可用，仍可手动开始"); return }
        guard !monitoring || !motion.isRunning else { return }
        monitoring = true; motionStatus = L10n.text("自动开始已开启"); motion.start(threshold: preferences.sensitivity)
    }
    private func authorizeHealthIfNeeded() {
        guard foregroundActive, healthAuthorizationPending, !healthAuthorizing else { return }
        healthAuthorizationPending = false; healthAuthorizing = true
        healthAuthorizationTask = Task { [weak self] in
            guard let self else { return }
            await self.health.authorize()
            self.healthAuthorizing = false
            if self.preferences.healthEnabled, let record = self.active, record.phase == .recording, !self.health.running {
                self.startHealthAndFeedback(for: record.id, at: self.clock(), cue: false)
            }
        }
    }
    func closeResult() { if let pending = engine?.record, pending.phase == .finished { result = pending; return }; result = nil; updateMonitoring() }
    func sceneChanged(_ phase: ScenePhase) {
        foregroundActive = phase == .active
        if phase != .active && monitoring { monitoring = false; motion.stop(); motionStatus = L10n.text("自动开始待机 · 返回 App 后恢复") }
        if recordsMotion, phase == .background && active?.phase == .recording && !health.running { pause(); motion.stop(); motionStatus = L10n.text("后台运行不可用，记录已暂停") }
        if phase == .active {
            motionRetryAfter = .distantPast
            connectivity.refresh(); updateMonitoring(); authorizeHealthIfNeeded(); deliverDeferredFeedback()
        }
        if phase != .active { persistCheckpoint() }
    }
    func continueAfterIdle() { lastMovement = clock(); idleCountdown = nil }
    func awaitHealthRecovery() async { await healthRecoveryTask?.value }
    func awaitHealthFinalization() async { await healthFinalizationTask?.value }
    func awaitHealthStart() async { await healthStartTask?.value }
    func awaitHealthAuthorization() async { await healthAuthorizationTask?.value }

    /// End an orphaned system workout; the local checkpoint stays interrupted for an explicit resume.
    func recoverHealthSession() {
        guard recordsMotion, !healthRecoveryPending else { return }
        healthRecoveryPending = true
        healthRecoveryTask = Task { [weak self] in
            guard let self else { return }
            await self.health.cleanupRecoveredWorkout()
            self.healthRecoveryPending = false
            self.updateMonitoring()
        }
    }
    private func startMotion() {
        motionStatus = motion.available ? L10n.text("动作采集中 · 次数为估算") : L10n.text("动作不可用 · 仅记时")
        motion.start(threshold: preferences.sensitivity)
    }
    private func invalidateHealthStart() {
        healthStartGeneration &+= 1; healthStartTask?.cancel(); healthStartTask = nil
    }
    private func startHealthAndFeedback(for id: UUID, at date: Date, cue: Bool = true) {
        invalidateHealthStart()
        let generation = healthStartGeneration
        if healthRecoveryPending || health.collectionCleanupPending {
            healthStartTask = Task { [weak self] in
                guard let self else { return }
                await self.healthRecoveryTask?.value
                await self.health.waitForCollectionEnd()
                guard !Task.isCancelled, self.healthStartGeneration == generation,
                      self.active?.id == id, self.active?.phase == .recording else { return }
                self.beginHealthCollection(at: date, cue: cue)
            }
        } else { beginHealthCollection(at: date, cue: cue) }
    }
    private func beginHealthCollection(at date: Date, cue: Bool) {
        if cue, let plan = feedbackPolicy.request(.start, isForeground: foregroundActive, sound: preferences.sound, haptics: preferences.haptics) {
            _ = feedbackOutput(plan)
        }
        if preferences.healthEnabled { health.start(at: date) }
    }
    private func finalizeHealth(for record: SessionRecord) {
        healthFinalizationTask = Task { [weak self] in
            guard let self else { return }
            await self.health.waitForCollectionEnd()
            self.deliverDeferredFeedback()
            await self.loadHearts(for: record)
        }
    }
    private func deliverDeferredFeedback() {
        guard !health.collectionCleanupPending else { return }
        // A very fast restart must not replay the previous finish cue during the new collection.
        let collecting = active?.phase == .recording
        if let plan = feedbackPolicy.takeDeferred(isForeground: foregroundActive,
                sound: collecting ? false : preferences.sound, haptics: collecting ? false : preferences.haptics) {
            _ = feedbackOutput(plan)
        }
    }
    private func handleHealthEvent(_ event: HealthSessionEvent) {
        guard var value = engine, value.record.phase != .finished else { return }
        let previous = value.record
        switch event {
        case .paused(let date): value.systemPause(at: date)
        case .resumed(let date): value.systemResume(at: date)
        case .interrupted(let date, let message): value.interrupt(at: date); motionStatus = message
        }
        guard value.record != previous else { return }
        // A system-ended collector cannot be kept recording even when the disk write fails.
        if value.record.phase != .recording { invalidateHealthStart() }
        engine = value; liveHeartSample = nil; idleCountdown = nil; monitoring = false
        if value.record.phase == .recording { lastMovement = clock(); if recordsMotion { startMotion() } }
        else { motion.stop() }
        persistCheckpoint()
    }
    func currentHeartRate(for record: SessionRecord) -> Double? {
        guard record.phase == .recording else { return record.latestHeartSample?.bpm }
        let candidates = active?.id == record.id ? [liveHeartSample, record.latestHeartSample] : [record.latestHeartSample]
        let sample = candidates.compactMap { $0 }.max { $0.date < $1.date }
        guard let sample, (0...30).contains(clock().timeIntervalSince(sample.date)) else { return nil }
        return sample.bpm
    }
    func tick(_ date: Date) {
        if recordsMotion { motion.checkSampling(at: date) }
        if foregroundActive, motion.available, preferences.automaticStart, !monitoring, engine == nil, result == nil, date >= cooldownUntil { updateMonitoring() }
        // Pausing commits immediately; only an advancing session needs timer-driven UI and disk updates.
        if engine?.record.phase == .recording {
            now = date
            engine?.checkpoint(at: date)
            if date.timeIntervalSince(lastPersist) >= 5 { persistCheckpoint() }
        }
        if recordsMotion, preferences.autoStop, engine?.record.phase == .recording, motion.hasFreshSamples(at: date) {
            let idle = date.timeIntervalSince(lastMovement)
            if idle >= preferences.idleSeconds { idleCountdown = max(0, 10 - Int(idle - preferences.idleSeconds)); if idleCountdown == 0 { finish() } }
        } else if idleCountdown != nil { idleCountdown = nil }
    }
    private func persistCheckpoint() { guard let active else { return }; do { try requireStore().checkpoint(active); lastPersist = clock() } catch { if errorMessage == nil { errorMessage = L10n.format("检查点保存失败：%@", error.localizedDescription) } } }
    @discardableResult private func mutate(_ operation: (inout SessionEngine) throws -> Void) -> Bool {
        guard var value = engine else { return false }
        do { try operation(&value); try requireStore().checkpoint(value.record); engine = value; now = value.record.lastCheckpoint; return true } catch { errorMessage = error.localizedDescription; return false }
    }
    private func requireStore() throws -> RecordStore { guard let store else { throw EnchantError.invalidRecord("资料库未就绪，请先处理读取错误。") }; return store }
    @discardableResult func save(_ record: SessionRecord) -> Bool {
        do { try requireStore().upsert(record); records = store!.document.records; sync(); return true } catch { errorMessage = error.localizedDescription; return false }
    }
    @discardableResult func delete(_ id: UUID) -> Bool { do { try requireStore().delete(id: id); records = store!.document.records; sync(); return true } catch { errorMessage = error.localizedDescription; return false } }
    func restore(_ id: UUID) { do { try requireStore().restore(id: id); records = store!.document.records; sync() } catch { errorMessage = error.localizedDescription } }
    @discardableResult func receiveArchive(_ data: Data) -> Bool {
        guard store != nil else { return false }
        do { if try requireStore().merge(data) { records = store!.document.records; sync() }; return true }
        catch {
            errorMessage = L10n.format("同步数据未接收，现有记录未更改：%@", error.localizedDescription)
            if error is DecodingError { return true }
            if let validation = error as? EnchantError {
                switch validation {
                case .unsupportedVersion, .invalidRecord, .invalidLink: return true
                case .oversizedArchive:
                    // A valid incoming archive can exceed capacity only after merging with local records.
                    // Keep that inbox for retry; reject permanently only when the input itself exceeds limits.
                    if data.count > 30_000_000 { return true }
                    return (try? JSONDecoder().decode(ArchiveDocument.self, from: data).records.count).map { $0 > 50_000 } ?? false
                case .invalidTransition: return false
                }
            }
            return false
        }
    }
    func sync() { if let data = try? store?.export() { connectivity.send(data) } }
    func createFreshStorePreservingOriginal() {
        do {
            let preserved = fileURL.deletingLastPathComponent().appendingPathComponent("archive-damaged-\(Int(clock().timeIntervalSince1970)).json")
            if FileManager.default.fileExists(atPath: fileURL.path) { try FileManager.default.moveItem(at: fileURL, to: preserved) }
            store = try RecordStore(fileURL: fileURL, writerID: writerID); records = []; engine = nil; loadError = nil
            connectivity.refresh()
        } catch { errorMessage = error.localizedDescription }
    }
    func loadHearts(for record: SessionRecord) async {
        guard preferences.healthEnabled, record.origin != .backfill, let end = record.endedAt else { return }
        do {
            let samples = try await health.heartSamples(start: record.startedAt, end: end)
            guard preferences.healthEnabled, !samples.isEmpty else { return }
            let pending = engine?.record.id == record.id && engine?.record.phase == .finished
            guard var current = pending ? engine?.record : records.first(where: { $0.id == record.id && $0.deletedAt == nil }) else { return }
            let original = current.heartSamples
            // Replace only our older provisional builder readings when canonical data is available.
            let retained = original.filter { !($0.identity == nil && $0.source == "Apple Watch · 本次健康会话") }
            var seen = Set<String>()
            current.heartSamples = (retained + samples).filter { sample in
                let key = sample.identity.map { "id:\($0)" } ?? "legacy:\(sample.date.timeIntervalSinceReferenceDate.bitPattern):\(sample.bpm.bitPattern):\(sample.source)"
                return seen.insert(key).inserted
            }.sorted { $0.date < $1.date }
            current.heartSamples = Array(current.validHeartSamples.prefix(20_000))
            // Reopening a detail must not create another revision or repeat a sync transfer.
            guard current.heartSamples != original else { return }
            if pending {
                // Preserve final sensor data for a save retry even if the checkpoint write also fails.
                engine = SessionEngine(record: current); result = current
                try requireStore().checkpoint(current)
            } else if save(current), result?.id == current.id { result = records.first { $0.id == current.id } }
        } catch { errorMessage = L10n.format("健康样本读取失败：%@", error.localizedDescription) }
    }
    private func persistPreferenceStamp() { defaults.set(preferenceRevision, forKey: "preferenceRevision"); defaults.set(preferenceWriter, forKey: "preferenceWriter") }
    private func syncPreferences() { if let data = try? JSONEncoder().encode(PreferencesEnvelope(revision: preferenceRevision, writerID: preferenceWriter, values: preferences)) { connectivity.sendPreferences(data) } }
    private func receivePreferences(_ data: Data) {
        guard let incoming = try? JSONDecoder().decode(PreferencesEnvelope.self, from: data), incoming.revision > 0,
              incoming.revision > preferenceRevision || (incoming.revision == preferenceRevision && incoming.writerID > preferenceWriter),
              [0.08, 0.12, 0.18].contains(incoming.values.sensitivity), [60.0, 90.0, 120.0].contains(incoming.values.idleSeconds) else { return }
        applyingRemotePreferences = true; var normalized = incoming.values; normalized.autoSave = true; normalized.writeWorkout = false; preferences = normalized; applyingRemotePreferences = false
        preferenceRevision = incoming.revision; preferenceWriter = incoming.writerID; persistPreferenceStamp()
    }
    #if DEBUG
    private func seedDemo() throws {
        let calendar = Calendar.current, today = clock()
        for offset in [0, 0, 1, 3, 5, 8, 12, 18] {
            let date = calendar.date(byAdding: .day, value: -offset, to: today)!.addingTimeInterval(-3600)
            var r = SessionRecord(startedAt: date, origin: .manual); r.endedAt = date.addingTimeInterval(208); r.lastCheckpoint = r.endedAt!; r.phase = .finished; r.note = "demo · 本地演示记录"; r.estimatedCycles = 126; r.motionSampleCount = nil
            r.heartSamples = (0..<20).map { HeartSample(date: date.addingTimeInterval(Double($0 * 10)), bpm: Double(88 + $0 % 6 * 4), source: "演示数据") }; try store!.upsert(r)
        }
        records = store!.document.records
    }
    #endif
}

extension AppModel {
    private func draftURL(_ key: String) -> URL { fileURL.deletingLastPathComponent().appendingPathComponent("drafts").appendingPathComponent(key.filter { $0.isLetter || $0.isNumber || $0 == "-" } + ".json") }
    func readDraft(key: String) -> Data? { try? Data(contentsOf: draftURL(key)) }
    func writeDraft(_ data: Data, key: String) {
        do {
            let url = draftURL(key); try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true); try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            var protectedURL = url; var values = URLResourceValues(); values.isExcludedFromBackup = true; try? protectedURL.setResourceValues(values)
        } catch { if errorMessage == nil { errorMessage = L10n.format("草稿未保存：%@", error.localizedDescription) } }
    }
    func removeDraft(key: String) { try? FileManager.default.removeItem(at: draftURL(key)) }
}
