import Foundation

/// Validates callback ownership and sensor progress separately from detected movement.
/// Sensor timestamps are boot-relative; only their differences are compared with delivery elapsed time.
public struct MotionAcquisitionState {
    public private(set) var generation = 0
    public private(set) var sampleCount = 0
    private var startedAt: Date?
    private var firstTimestamp: TimeInterval?
    private var firstDelivery: Date?
    private var lastTimestamp: TimeInterval?
    private var lastDelivery: Date?
    private let firstSampleTimeout: TimeInterval = 3
    private let stallTimeout: TimeInterval = 2
    private let maximumTimestampDrift: TimeInterval = 1

    public init() {}

    @discardableResult public mutating func start(at date: Date) -> Int {
        generation &+= 1; sampleCount = 0; startedAt = date
        firstTimestamp = nil; firstDelivery = nil; lastTimestamp = nil; lastDelivery = nil
        return generation
    }

    public mutating func stop() {
        generation &+= 1; startedAt = nil; firstTimestamp = nil; firstDelivery = nil
        lastTimestamp = nil; lastDelivery = nil; sampleCount = 0
    }

    public func accepts(generation token: Int) -> Bool { startedAt != nil && generation == token }

    public mutating func consume(timestamp: TimeInterval, deliveredAt date: Date, generation token: Int) -> Bool {
        guard accepts(generation: token), timestamp.isFinite, timestamp >= 0,
              date.timeIntervalSince1970.isFinite, let start = startedAt, date >= start,
              lastTimestamp == nil || timestamp > lastTimestamp!,
              lastDelivery == nil || date >= lastDelivery!, !hasTimedOut(at: date) else { return false }
        if let initialTimestamp = firstTimestamp, let initialDelivery = firstDelivery {
            let drift = date.timeIntervalSince(initialDelivery) - (timestamp - initialTimestamp)
            guard abs(drift) <= maximumTimestampDrift else { return false }
        } else {
            firstTimestamp = timestamp; firstDelivery = date
        }
        lastTimestamp = timestamp; lastDelivery = date; sampleCount += 1
        return true
    }

    public func hasFreshSamples(at date: Date) -> Bool {
        guard startedAt != nil, let delivery = lastDelivery else { return false }
        let age = date.timeIntervalSince(delivery)
        return age.isFinite && age >= 0 && age < stallTimeout
    }

    public func hasTimedOut(at date: Date) -> Bool {
        guard let start = startedAt else { return false }
        let age = date.timeIntervalSince(lastDelivery ?? start)
        return !age.isFinite || age < 0 || age >= (lastDelivery == nil ? firstSampleTimeout : stallTimeout)
    }
}
