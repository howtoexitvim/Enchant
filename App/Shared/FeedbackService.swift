import AVFoundation
import OSLog
#if os(watchOS)
import WatchKit
#else
import UIKit
#endif
@MainActor final class FeedbackService {
    private var player: AVAudioPlayer?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.shuqi.enchant", category: "Feedback")
    private(set) var lastSoundError: String?

    /// The caller applies foreground policy and avoids haptics while HealthKit collects heart rate.
    @discardableResult func play(_ plan: FeedbackPlan) -> Bool {
        lastSoundError = nil
        do {
            let accepted = try plan.deliver(haptic: playHaptic, sound: playSound)
            if !accepted { report(SoundError.playbackRejected) }
            return accepted
        } catch {
            report(error)
            return false
        }
    }

    private func playHaptic(_ cue: FeedbackCue) {
        // WatchKit patterns may include a system tone; the sound preference gates our WAV only.
        #if os(watchOS)
        WKInterfaceDevice.current().play(cue == .finish ? .success : .start)
        #else
        if cue == .finish { UINotificationFeedbackGenerator().notificationOccurred(.success) }
        else { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
        #endif
    }

    private func playSound(_ cue: FeedbackCue) throws -> Bool {
        let name = cue == .finish ? "enchant-finish" : "enchant-start"
        guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else { throw SoundError.missingResource(name) }
        player?.stop(); player = nil
        // Optional effects mix with other audio and retain the system's silence policy.
        try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
        let next = try AVAudioPlayer(contentsOf: url)
        guard next.play() else { return false }
        player = next
        return true
    }

    private func report(_ error: Error) {
        let message = error.localizedDescription
        lastSoundError = message
        logger.error("Sound cue failed: \(message, privacy: .public)")
    }

    private enum SoundError: LocalizedError {
        case missingResource(String), playbackRejected
        var errorDescription: String? {
            switch self {
            case .missingResource(let name): return "Missing feedback audio resource: \(name).wav"
            case .playbackRejected: return "Audio playback did not start."
            }
        }
    }
}
