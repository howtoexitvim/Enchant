import Foundation
import HealthKit
import Combine

enum HealthSessionEvent {
    case paused(Date)
    case resumed(Date)
    case interrupted(Date, String)
}

@MainActor protocol HealthCollecting: AnyObject {
    var status: String { get }
    var running: Bool { get }
    var available: Bool { get }
    var recoveryInProgress: Bool { get }
    var collectionCleanupPending: Bool { get }
    var onHeartSample: ((HeartSample) -> Void)? { get set }
    var onLiveHeartSample: ((HeartSample) -> Void)? { get set }
    var onSessionEvent: ((HealthSessionEvent) -> Void)? { get set }
    func authorize() async
    func start(at date: Date)
    func pause()
    func resume()
    func stop(writeWorkout: Bool)
    func waitForCollectionEnd() async
    func heartSamples(start: Date, end: Date) async throws -> [HeartSample]
    func cleanupRecoveredWorkout() async
}

@MainActor final class HealthService: NSObject, ObservableObject, HealthCollecting {
    let store = HKHealthStore()
    @Published var status = L10n.text("未开启健康采集")
    @Published var running = false
    @Published private(set) var recoveryInProgress = false
    var onHeartSample: ((HeartSample) -> Void)?
    var onLiveHeartSample: ((HeartSample) -> Void)?
    var onSessionEvent: ((HealthSessionEvent) -> Void)?
    #if os(watchOS)
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var heartStream: Task<Void, Never>?
    private var collectionCleanup: Task<Void, Never>?
    private var endingSession: HKWorkoutSession?
    private var stoppedContinuation: CheckedContinuation<Void, Never>?
    private var pendingFailureMessage: String?
    #endif
    var available: Bool { HKHealthStore.isHealthDataAvailable() }
    var collectionCleanupPending: Bool {
        #if os(watchOS)
        collectionCleanup != nil
        #else
        false
        #endif
    }

    func authorize() async {
        guard available else { status = L10n.text("此设备不支持健康数据，仍可手动记录。"); return }
        let read: Set<HKObjectType> = [HKQuantityType(.heartRate)]
        do {
            #if os(watchOS)
            try await store.requestAuthorization(toShare: [HKObjectType.workoutType()], read: read)
            #else
            try await store.requestAuthorization(toShare: [], read: read)
            #endif
            // HealthKit deliberately does not expose denied read permission.
            status = L10n.text("授权请求已完成；没有可读取样本时显示未获取。")
        } catch { status = L10n.format("健康授权未完成：%@", error.localizedDescription) }
    }

    func start(at date: Date) {
        #if os(watchOS)
        guard available, !recoveryInProgress, collectionCleanup == nil, session == nil else { return }
        guard store.authorizationStatus(for: .workoutType()) == .sharingAuthorized else {
            status = L10n.text("未获会话授权，使用本地记时与动作采集。"); return
        }
        let config = HKWorkoutConfiguration()
        config.activityType = .other
        config.locationType = .unknown
        do {
            let workout = try HKWorkoutSession(healthStore: store, configuration: config)
            let liveBuilder = workout.associatedWorkoutBuilder()
            liveBuilder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
            workout.delegate = self
            liveBuilder.delegate = self
            session = workout
            builder = liveBuilder
            pendingFailureMessage = nil
            workout.startActivity(with: date)
            liveBuilder.beginCollection(withStart: date) { [weak self] success, error in
                Task { @MainActor in
                    guard let self, self.session === workout else { return }
                    if success {
                        self.status = L10n.text("健康会话运行中，等待有效心率样本")
                        self.observeHeartSamples(for: workout, start: date)
                    } else {
                        self.handleInterruption(workout, at: Date(), message: error?.localizedDescription ?? L10n.text("健康采集未启动"))
                    }
                }
            }
        } catch { status = L10n.format("健康会话未启动：%@", error.localizedDescription) }
        #else
        status = L10n.text("iPhone 将读取本次时间范围内的已有健康样本。")
        #endif
    }

    #if os(watchOS)
    private func handleInterruption(_ failed: HKWorkoutSession, at date: Date, message: String) {
        guard session === failed else { return }
        let previous = builder
        session = nil
        builder = nil
        pendingFailureMessage = nil
        heartStream?.cancel()
        heartStream = nil
        running = false
        status = message
        // A collection error does not itself end the independently started session.
        failed.end()
        previous?.discardWorkout()
        onSessionEvent?(.interrupted(date, message))
    }

    private func observeHeartSamples(for workout: HKWorkoutSession, start: Date) {
        heartStream?.cancel()
        heartStream = Task { [weak self] in
            guard let self else { return }
            let type = HKQuantityType(.heartRate)
            let predicate = HKQuery.predicateForSamples(withStart: start, end: nil, options: [])
            let descriptor = HKAnchoredObjectQueryDescriptor(predicates: [.quantitySample(type: type, predicate: predicate)], anchor: nil)
            var expandedContainers = Set<UUID>()
            do {
                for try await update in descriptor.results(for: self.store) {
                    try Task.checkCancellation()
                    guard self.session === workout else { return }
                    let fresh = Set(update.addedSamples.compactMap { sample in
                        expandedContainers.insert(sample.uuid).inserted ? sample.uuid : nil
                    })
                    guard !fresh.isEmpty else { continue }
                    // The anchor supplies only new containers; expand each immutable container once.
                    let samples = try await self.individualHeartSamples(
                        predicate: HKQuery.predicateForObjects(with: fresh), start: start, end: Date()
                    )
                    try Task.checkCancellation()
                    guard self.session === workout else { return }
                    for sample in samples { self.onHeartSample?(sample) }
                }
            } catch is CancellationError {
                // Stopping a session also stops its HealthKit query sequence.
            } catch {
                guard self.session === workout else { return }
                self.status = L10n.format("健康样本读取失败：%@", error.localizedDescription)
            }
        }
    }
    #endif

    func pause() {
        #if os(watchOS)
        session?.pause()
        #endif
    }

    func resume() {
        #if os(watchOS)
        session?.resume()
        #endif
    }

    func stop(writeWorkout: Bool) {
        #if os(watchOS)
        let workout = session
        let previous = builder
        session = nil
        builder = nil
        pendingFailureMessage = nil
        heartStream?.cancel()
        heartStream = nil
        running = false
        guard workout != nil || previous != nil else { return }
        let end = Date()
        endingSession = workout
        collectionCleanup = Task {
            if let workout, workout.state == .running || workout.state == .paused {
                await withCheckedContinuation { continuation in
                    self.stoppedContinuation = continuation
                    workout.stopActivity(with: end)
                }
            } else { workout?.end() }
            if let previous {
                do { try await previous.endCollection(at: end) }
                catch { self.status = L10n.format("健康会话中断：%@", error.localizedDescription) }
                // Enchant keeps its own journal and never finishes/saves this workout.
                previous.discardWorkout()
            }
            workout?.end()
            self.endingSession = nil
            self.collectionCleanup = nil
        }
        #endif
    }

    func waitForCollectionEnd() async {
        #if os(watchOS)
        await collectionCleanup?.value
        #endif
    }

    func cleanupRecoveredWorkout() async {
        #if os(watchOS)
        guard available, !recoveryInProgress, collectionCleanup == nil, session == nil else { return }
        recoveryInProgress = true
        defer { recoveryInProgress = false }
        do {
            guard let recovered = try await store.recoverActiveWorkoutSession() else { return }
            let recoveredBuilder = recovered.associatedWorkoutBuilder()
            recovered.end()
            recoveredBuilder.discardWorkout()
        } catch { status = L10n.format("健康会话中断：%@", error.localizedDescription) }
        #endif
    }

    func heartSamples(start: Date, end: Date) async throws -> [HeartSample] {
        guard available, end >= start else { return [] }
        // Overlapping series containers may begin before or end after the journal interval.
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        return try await individualHeartSamples(predicate: predicate, start: start, end: end)
    }

    private func individualHeartSamples(predicate: NSPredicate, start: Date, end: Date) async throws -> [HeartSample] {
        let descriptor = HKQuantitySeriesSampleQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(.heartRate), predicate: predicate), options: [.includeSample]
        )
        var samples: [HeartSample] = []
        var identities = Set<String>()
        for try await entry in descriptor.results(for: store) {
            try Task.checkCancellation()
            guard let container = entry.sample else { continue }
            let date = entry.dateInterval.start
            let bpm = entry.quantity.doubleValue(for: .count().unitDivided(by: .minute()))
            guard date >= start, date <= end, date.timeIntervalSince1970.isFinite,
                  bpm.isFinite, (20...300).contains(bpm) else { continue }
            let identity = "\(container.uuid.uuidString):\(date.timeIntervalSinceReferenceDate.bitPattern):\(entry.dateInterval.end.timeIntervalSinceReferenceDate.bitPattern)"
            guard identities.insert(identity).inserted else { continue }
            samples.append(HeartSample(date: date, bpm: bpm, source: container.sourceRevision.source.name, identity: identity))
            if samples.count == 20_000 { break }
        }
        return samples.sorted { $0.date < $1.date }
    }
}

#if os(watchOS)
extension HealthService: HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            if self.endingSession === workoutSession {
                if toState == .stopped || toState == .ended {
                    self.stoppedContinuation?.resume()
                    self.stoppedContinuation = nil
                }
                return
            }
            guard self.session === workoutSession else { return }
            switch toState {
            case .running:
                self.running = true
                if fromState == .paused { self.onSessionEvent?(.resumed(date)) }
            case .paused:
                // A paused workout still owns its background runtime.
                self.running = true
                self.onSessionEvent?(.paused(date))
            case .stopped, .ended:
                self.handleInterruption(workoutSession, at: date, message: self.pendingFailureMessage ?? L10n.text("健康会话已被系统结束，记录已中断保留。"))
            default: break
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            if self.endingSession === workoutSession {
                self.stoppedContinuation?.resume()
                self.stoppedContinuation = nil
                return
            }
            guard self.session === workoutSession else { return }
            // HealthKit sends the failure before its dated state-change notification.
            self.pendingFailureMessage = L10n.format("健康会话中断：%@", error.localizedDescription)
            self.running = false
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let type = HKQuantityType(.heartRate)
        guard collectedTypes.contains(type), let statistics = workoutBuilder.statistics(for: type),
              let quantity = statistics.mostRecentQuantity(), let interval = statistics.mostRecentQuantityDateInterval() else { return }
        let bpm = quantity.doubleValue(for: .count().unitDivided(by: .minute()))
        guard bpm.isFinite, (20...300).contains(bpm) else { return }
        // A builder statistic is only a current display value. Canonical raw series alone enter the archive.
        let source = statistics.sources?.count == 1 ? statistics.sources?.first?.name ?? "HealthKit" : "HealthKit"
        let sample = HeartSample(date: interval.start, bpm: bpm, source: source)
        Task { @MainActor in
            guard self.builder === workoutBuilder else { return }
            self.onLiveHeartSample?(sample)
        }
    }
}
#endif
