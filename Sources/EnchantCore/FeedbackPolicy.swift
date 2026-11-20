import Foundation

public enum FeedbackCue: String { case start, finish }

public struct FeedbackPlan {
    public let cue: FeedbackCue
    public let sound: Bool
    public let haptics: Bool
    public init(cue: FeedbackCue, sound: Bool, haptics: Bool) { self.cue = cue; self.sound = sound; self.haptics = haptics }
    /// Returns whether the enabled output requests were accepted, not whether a person felt or heard them.
    public func deliver(haptic: (FeedbackCue) -> Void, sound: (FeedbackCue) throws -> Bool) rethrows -> Bool {
        if haptics { haptic(cue) }
        return self.sound ? try sound(cue) : true
    }
}

public struct FeedbackPolicy {
    private var deferredFinish = false
    public init() {}
    /// Start cues require the foreground. Background completion waits for one foreground return.
    public mutating func request(_ cue: FeedbackCue, isForeground: Bool, sound: Bool, haptics: Bool) -> FeedbackPlan? {
        guard sound || haptics else {
            if cue == .finish { deferredFinish = false }
            return nil
        }
        guard isForeground else {
            if cue == .finish { deferredFinish = true }
            return nil
        }
        if cue == .finish { deferredFinish = false }
        return FeedbackPlan(cue: cue, sound: sound, haptics: haptics)
    }
    /// Consume before delivery, so failed output cannot replay on a later scene change.
    public mutating func takeDeferred(isForeground: Bool, sound: Bool, haptics: Bool) -> FeedbackPlan? {
        guard isForeground, deferredFinish else { return nil }
        deferredFinish = false
        return request(.finish, isForeground: true, sound: sound, haptics: haptics)
    }
}
