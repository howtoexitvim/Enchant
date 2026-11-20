import Foundation

/// A wrist-acceleration heuristic, not a physiological event detector.
/// The initial sign is a baseline. Two subsequent qualified reversals estimate one cycle.
public struct MotionDetector {
    public var threshold: Double
    public private(set) var cycleCount = 0
    public private(set) var lastActivity: TimeInterval = 0
    private var lastSign = 0
    private var partialReversals = 0
    private var lastReversal: TimeInterval?
    private var lastSample: TimeInterval?
    private var burstStartedAt: TimeInterval?
    private var reversals: [TimeInterval] = []

    public init(threshold: Double = 0.12) { self.threshold = threshold }

    /// Discards an incomplete cycle and candidate window while retaining completed cycles.
    public mutating func resetBurst() {
        lastSign = 0; partialReversals = 0; lastReversal = nil
        burstStartedAt = nil; reversals.removeAll(keepingCapacity: true)
    }

    public mutating func consume(acceleration: Double, time: TimeInterval) -> Bool {
        guard acceleration.isFinite, time.isFinite, threshold.isFinite, threshold > 0,
              lastSample == nil || time > lastSample! else { return false }
        lastSample = time
        // Expire before sign/threshold rejection so a same-sign return cannot bridge a pause.
        if let last = lastReversal, time - last > 1.5 { resetBurst() }
        guard abs(acceleration) >= threshold else { return false }
        let sign = acceleration > 0 ? 1 : -1
        if lastSign == 0 {
            lastSign = sign; lastReversal = time; burstStartedAt = time; lastActivity = time
            return false
        }
        guard sign != lastSign, let last = lastReversal, time - last >= 0.15 else { return false }
        lastSign = sign; lastReversal = time; lastActivity = time
        reversals.append(time)
        if reversals.count > 10 { reversals.removeFirst() }
        partialReversals += 1
        if partialReversals == 2 { cycleCount += 1; partialReversals = 0 }
        guard reversals.count >= 8, let start = burstStartedAt, time - start >= 3 else { return false }
        let intervals = zip(reversals.dropFirst(), reversals).map(-)
        let mean = intervals.reduce(0, +) / Double(intervals.count)
        let variance = intervals.map { pow($0 - mean, 2) }.reduce(0, +) / Double(intervals.count)
        return mean > 0 && sqrt(variance) / mean < 0.35
    }
}
