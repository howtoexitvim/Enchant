import Foundation
import XCTest
@testable import EnchantCore

final class FeedbackTests: XCTestCase {
    func testEachPreferenceCombinationRequestsOnlyItsEnabledOutputs() throws {
        // A removed preference gate would request an output that this table forbids.
        let cases: [(sound: Bool, haptics: Bool, outputs: [String])] = [
            (true, true, ["haptic:start", "sound:start"]),
            (true, false, ["sound:start"]),
            (false, true, ["haptic:start"]),
            (false, false, [])
        ]
        for item in cases {
            var policy = FeedbackPolicy()
            let plan = policy.request(.start, isForeground: true, sound: item.sound, haptics: item.haptics)
            var outputs: [String] = []
            let accepted = plan?.deliver(
                haptic: { outputs.append("haptic:\($0.rawValue)") },
                sound: { outputs.append("sound:\($0.rawValue)"); return true }
            )
            XCTAssertEqual(outputs, item.outputs)
            if item.sound || item.haptics { XCTAssertEqual(accepted, true) }
        }
    }

    func testForegroundFinishDoesNotLeaveASecondCueForForegroundReturn() throws {
        // Incorrectly queuing a foreground event would replay it on the next scene change.
        var policy = FeedbackPolicy()
        let plan = try XCTUnwrap(policy.request(.finish, isForeground: true, sound: true, haptics: true))
        var sounds: [FeedbackCue] = []
        XCTAssertTrue(plan.deliver(haptic: { _ in }, sound: { sounds.append($0); return true }))
        XCTAssertEqual(sounds, [.finish])
        XCTAssertNil(policy.takeDeferred(isForeground: true, sound: true, haptics: true))
    }

    func testBackgroundCompletionCoalescesAndIsConsumedOnceWithCurrentPreferences() throws {
        // Failing to clear pending completion would repeat feedback on every foreground return.
        var policy = FeedbackPolicy()
        XCTAssertNil(policy.request(.finish, isForeground: false, sound: true, haptics: true))
        XCTAssertNil(policy.request(.finish, isForeground: false, sound: true, haptics: true))
        XCTAssertNil(policy.takeDeferred(isForeground: false, sound: true, haptics: true))
        let plan = try XCTUnwrap(policy.takeDeferred(isForeground: true, sound: false, haptics: true))
        var outputs: [String] = []
        XCTAssertTrue(plan.deliver(haptic: { outputs.append("haptic:\($0.rawValue)") }, sound: { outputs.append("sound:\($0.rawValue)"); return true }))
        XCTAssertEqual(outputs, ["haptic:finish"])
        XCTAssertNil(policy.takeDeferred(isForeground: true, sound: true, haptics: true))
    }

    func testDisabledCompletionDoesNotBecomeAnAlertAfterPreferencesChange() {
        // Queuing a disabled event would produce a stale cue when the person later enables sound.
        var policy = FeedbackPolicy()
        XCTAssertNil(policy.request(.finish, isForeground: false, sound: false, haptics: false))
        XCTAssertNil(policy.takeDeferred(isForeground: true, sound: true, haptics: true))
    }

    func testDisablingBothChannelsConsumesAnAlreadyDeferredCompletion() {
        var policy = FeedbackPolicy()
        XCTAssertNil(policy.request(.finish, isForeground: false, sound: true, haptics: true))
        XCTAssertNil(policy.takeDeferred(isForeground: true, sound: false, haptics: false))
        XCTAssertNil(policy.takeDeferred(isForeground: true, sound: true, haptics: true))
    }

    func testBackgroundStartIsNotReplayedOnForegroundReturn() {
        var policy = FeedbackPolicy()
        XCTAssertNil(policy.request(.start, isForeground: false, sound: true, haptics: true))
        XCTAssertNil(policy.takeDeferred(isForeground: true, sound: true, haptics: true))
    }

    func testRejectedSoundIsReportedWithoutRetryingEitherOutput() throws {
        let plan = FeedbackPlan(cue: .finish, sound: true, haptics: true)
        var outputs: [String] = []
        XCTAssertFalse(plan.deliver(haptic: { outputs.append("haptic:\($0.rawValue)") }, sound: { outputs.append("sound:\($0.rawValue)"); return false }))
        XCTAssertEqual(outputs, ["haptic:finish", "sound:finish"])
    }

    func testSoundErrorPropagatesAfterTheIndependentHapticRequest() {
        enum Failure: Error { case unavailable }
        let plan = FeedbackPlan(cue: .start, sound: true, haptics: true)
        var outputs: [String] = []
        XCTAssertThrowsError(try plan.deliver(haptic: { outputs.append("haptic:\($0.rawValue)") }, sound: { outputs.append("sound:\($0.rawValue)"); throw Failure.unavailable }))
        XCTAssertEqual(outputs, ["haptic:start", "sound:start"])
    }

    func testBundledStartAndFinishResourcesAreNonemptyShortPCMClips() throws {
        // Missing, silent, truncated or misaligned audio assets must fail before shipping.
        let root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for name in ["enchant-start", "enchant-finish"] {
            let data = try Data(contentsOf: root.appendingPathComponent("App/Resources/\(name).wav"))
            try assertShortPCMClip(data, name: name)
        }
    }

    private func assertShortPCMClip(_ data: Data, name: String, file: StaticString = #filePath, line: UInt = #line) throws {
        XCTAssertGreaterThan(data.count, 44, name, file: file, line: line)
        guard data.count > 44 else { return }
        func text(_ offset: Int) -> String { String(decoding: data[offset..<(offset + 4)], as: UTF8.self) }
        func u16(_ offset: Int) -> Int { Int(data[offset]) | Int(data[offset + 1]) << 8 }
        func u32(_ offset: Int) -> Int { u16(offset) | u16(offset + 2) << 16 }
        XCTAssertEqual(text(0), "RIFF", name, file: file, line: line)
        XCTAssertEqual(text(8), "WAVE", name, file: file, line: line)
        XCTAssertEqual(u32(4) + 8, data.count, name, file: file, line: line)
        var format: (rate: Int, align: Int)?
        var payload: Data?
        var offset = 12
        while offset + 8 <= data.count {
            let length = u32(offset + 4), start = offset + 8
            guard length <= data.count - start else { XCTFail("Truncated \(name) chunk", file: file, line: line); return }
            if text(offset) == "fmt " {
                guard length >= 16 else { XCTFail("Incomplete \(name) format", file: file, line: line); return }
                let channels = u16(start + 2), rate = u32(start + 4), align = u16(start + 12), bits = u16(start + 14)
                XCTAssertEqual(u16(start), 1, "\(name) must use uncompressed PCM", file: file, line: line)
                XCTAssertTrue((1...2).contains(channels), name, file: file, line: line)
                XCTAssertEqual(bits, 16, name, file: file, line: line)
                XCTAssertEqual(align, channels * 2, name, file: file, line: line)
                XCTAssertGreaterThan(rate, 0, name, file: file, line: line)
                XCTAssertEqual(u32(start + 8), rate * align, name, file: file, line: line)
                format = (rate, align)
            } else if text(offset) == "data" { payload = Data(data[start..<(start + length)]) }
            offset = start + length + length % 2
        }
        let info = try XCTUnwrap(format, name, file: file, line: line)
        let samples = try XCTUnwrap(payload, name, file: file, line: line)
        guard info.rate > 0, info.align > 0 else { return }
        XCTAssertFalse(samples.isEmpty, name, file: file, line: line)
        XCTAssertEqual(samples.count % info.align, 0, name, file: file, line: line)
        XCTAssertTrue(samples.contains { $0 != 0 }, "\(name) must contain audible samples", file: file, line: line)
        let duration = Double(samples.count) / Double(info.rate * info.align)
        XCTAssertGreaterThan(duration, 0, name, file: file, line: line)
        XCTAssertLessThanOrEqual(duration, 1, "\(name) must remain a short feedback cue", file: file, line: line)
    }
}
