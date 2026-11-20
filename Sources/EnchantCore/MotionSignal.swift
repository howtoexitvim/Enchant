import Foundation

/// Counts only coherent reversals of one acceleration axis at a time.
/// A change of dominant axis begins a new burst instead of inventing a sign reversal.
public struct MotionSignal {
    private var detector: MotionDetector
    private var axis: Int?
    private var lastSample: TimeInterval?
    public var cycleCount: Int { detector.cycleCount }
    public var lastActivity: TimeInterval { detector.lastActivity }

    public init(threshold: Double = 0.12) { detector = MotionDetector(threshold: threshold) }

    public mutating func consume(x: Double, y: Double, z: Double, time: TimeInterval) -> Bool {
        guard x.isFinite, y.isFinite, z.isFinite, time.isFinite,
              lastSample == nil || time > lastSample! else { return false }
        lastSample = time
        let values = [x, y, z]
        let dominant = values.indices.max(by: { abs(values[$0]) < abs(values[$1]) })!
        if abs(values[dominant]) >= detector.threshold, axis != dominant {
            detector.resetBurst(); axis = dominant
        }
        return detector.consume(acceleration: axis.map { values[$0] } ?? 0, time: time)
    }
}
