import Foundation
import CoreMotion

@MainActor protocol MotionCapturing: AnyObject {
    var available: Bool { get }
    var isRunning: Bool { get }
    var onUpdate: ((Bool, Int) -> Void)? { get set }
    var onSample: (() -> Void)? { get set }
    var onActivity: (() -> Void)? { get set }
    var onFailure: ((String) -> Void)? { get set }
    func start(threshold: Double)
    func stop()
    func hasFreshSamples(at date: Date) -> Bool
    func checkSampling(at date: Date)
}

@MainActor final class MotionService: MotionCapturing {
    private let manager = CMMotionManager()
    private var signal = MotionSignal()
    private var acquisition = MotionAcquisitionState()
    private var count = 0
    private var threshold = 0.12
    private(set) var isRunning = false
    var onUpdate: ((Bool, Int) -> Void)?
    var onSample: (() -> Void)?
    var onActivity: (() -> Void)?
    var onFailure: ((String) -> Void)?
    var available: Bool { manager.isDeviceMotionAvailable }

    func start(threshold: Double) {
        stop()
        self.threshold = threshold.isFinite && threshold > 0 ? threshold : 0.12
        signal = MotionSignal(threshold: self.threshold); count = 0
        guard available else { onFailure?(L10n.text("此设备暂时无法采集动作，仍可手动记时。")); return }
        let generation = acquisition.start(at: Date())
        isRunning = true
        manager.deviceMotionUpdateInterval = 0.05
        manager.startDeviceMotionUpdates(to: .main) { [weak self] data, error in
            guard let self, self.isRunning, self.acquisition.accepts(generation: generation) else { return }
            if let error { self.stop(); self.onFailure?(error.localizedDescription); return }
            guard let data else { return }
            let a = data.userAcceleration
            guard a.x.isFinite, a.y.isFinite, a.z.isFinite,
                  self.acquisition.consume(timestamp: data.timestamp, deliveredAt: Date(), generation: generation) else { return }
            let candidate = self.signal.consume(x: a.x, y: a.y, z: a.z, time: data.timestamp)
            let delta = self.signal.cycleCount - self.count; self.count = self.signal.cycleCount
            self.onSample?()
            guard self.acquisition.accepts(generation: generation) else { return }
            if max(abs(a.x), abs(a.y), abs(a.z)) >= self.threshold { self.onActivity?() }
            guard self.acquisition.accepts(generation: generation) else { return }
            self.onUpdate?(candidate, max(0, delta))
        }
    }

    func hasFreshSamples(at date: Date = Date()) -> Bool { isRunning && acquisition.hasFreshSamples(at: date) }

    /// Called by the app's session timer; absent/stalled data must not be treated as stillness.
    func checkSampling(at date: Date = Date()) {
        guard isRunning, acquisition.hasTimedOut(at: date) else { return }
        stop(); onFailure?(L10n.text("此设备暂时无法采集动作，仍可手动记时。"))
    }

    func stop() {
        acquisition.stop(); isRunning = false; manager.stopDeviceMotionUpdates()
    }
}
