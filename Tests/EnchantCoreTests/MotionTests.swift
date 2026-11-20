import XCTest
@testable import EnchantCore

final class MotionTests: XCTestCase {
    // Counting the initial sign as a reversal would complete this cycle too early.
    func testFirstSignIsBaselineAndTwoReversalsCompleteOneCycle() {
        var detector = MotionDetector()
        XCTAssertFalse(detector.consume(acceleration: 0.4, time: 0))
        XCTAssertFalse(detector.consume(acceleration: -0.4, time: 0.4))
        XCTAssertEqual(detector.cycleCount, 0)
        XCTAssertFalse(detector.consume(acceleration: 0.4, time: 0.8))
        XCTAssertEqual(detector.cycleCount, 1)
    }

    // A pause must discard an incomplete cycle, even if the next sign matches.
    func testGapExpiresPartialCycleBeforeSameSignReacquisition() {
        var detector = MotionDetector()
        for (a, t) in [(0.4, 0.0), (-0.4, 0.4), (-0.4, 5.0), (0.4, 5.4)] {
            _ = detector.consume(acceleration: a, time: t)
        }
        XCTAssertEqual(detector.cycleCount, 0)
        _ = detector.consume(acceleration: -0.4, time: 5.8)
        XCTAssertEqual(detector.cycleCount, 1)
    }

    func testLongGapDoesNotJoinSeparateMovementsAndKeepsCompletedCycles() {
        var detector = MotionDetector()
        for (a, t) in [(0.4, 0.0), (-0.4, 0.4), (0.4, 0.8), (-0.4, 1.2), (0.4, 3600.0)] {
            _ = detector.consume(acceleration: a, time: t)
        }
        XCTAssertEqual(detector.cycleCount, 1)
        _ = detector.consume(acceleration: -0.4, time: 3600.4)
        XCTAssertEqual(detector.cycleCount, 1)
    }

    // Rapid noise can fill a reversal window without lasting long enough to start.
    func testRapidBurstDoesNotStartAutomatically() {
        var detector = MotionDetector()
        for i in 0..<12 {
            XCTAssertFalse(detector.consume(acceleration: i % 2 == 0 ? 0.4 : -0.4, time: Double(i) * 0.16))
        }
        XCTAssertEqual(detector.cycleCount, 5)
    }

    func testAutomaticCandidateRequiresEightActualReversalsAndThreeSeconds() {
        var detector = MotionDetector()
        for i in 0..<8 {
            XCTAssertFalse(detector.consume(acceleration: i % 2 == 0 ? 0.4 : -0.4, time: Double(i) * 0.4))
        }
        XCTAssertTrue(detector.consume(acceleration: 0.4, time: 3.2))
        XCTAssertEqual(detector.cycleCount, 4)
    }

    func testCadenceGapClearsAutomaticCandidate() {
        var detector = MotionDetector()
        for i in 0...8 { _ = detector.consume(acceleration: i % 2 == 0 ? 0.4 : -0.4, time: Double(i) * 0.4) }
        XCTAssertFalse(detector.consume(acceleration: -0.4, time: 6))
        XCTAssertEqual(detector.cycleCount, 4)
    }

    func testInvalidAndOutOfOrderSamplesDoNotCreateCycles() {
        var detector = MotionDetector()
        _ = detector.consume(acceleration: 0.4, time: 10)
        for (a, t) in [(Double.nan, 11.0), (0.4, Double.infinity), (-0.4, 9.0), (-0.4, 10.0), (-0.4, 10.1), (-0.05, 10.2)] {
            XCTAssertFalse(detector.consume(acceleration: a, time: t))
        }
        XCTAssertEqual(detector.cycleCount, 0)
        _ = detector.consume(acceleration: -0.4, time: 10.4)
        _ = detector.consume(acceleration: 0.4, time: 10.8)
        XCTAssertEqual(detector.cycleCount, 1)
    }
}

extension MotionTests {
    // Switching dominance of axes with fixed signs cannot constitute a reversal.
    func testDominanceSwitchDoesNotInventVectorCyclesOrAutomaticStart() {
        var signal = MotionSignal()
        for i in 0..<20 {
            let x = i % 2 == 0 ? 0.4 : 0.3
            let y = i % 2 == 0 ? -0.3 : -0.4
            XCTAssertFalse(signal.consume(x: x, y: y, z: 0, time: Double(i) * 0.4))
        }
        XCTAssertEqual(signal.cycleCount, 0)
    }

    func testCoherentMotionCountsOnEachAxis() {
        for axis in 0..<3 {
            var signal = MotionSignal()
            var detected = false
            for i in 0...8 {
                var vector = [0.01, 0.01, 0.01]
                vector[axis] = i % 2 == 0 ? 0.4 : -0.4
                detected = signal.consume(x: vector[0], y: vector[1], z: vector[2], time: Double(i) * 0.4) || detected
            }
            XCTAssertEqual(signal.cycleCount, 4)
            XCTAssertTrue(detected)
        }
    }

    func testAxisChangeDiscardsHalfCycleAndRetainsCompletedCount() {
        var signal = MotionSignal()
        _ = signal.consume(x: 0.4, y: 0, z: 0, time: 0)
        _ = signal.consume(x: -0.4, y: 0, z: 0, time: 0.4)
        _ = signal.consume(x: 0.4, y: 0, z: 0, time: 0.8)
        _ = signal.consume(x: -0.4, y: 0, z: 0, time: 1.2)
        _ = signal.consume(x: 0, y: 0.4, z: 0, time: 1.6)
        _ = signal.consume(x: 0, y: -0.4, z: 0, time: 2.0)
        XCTAssertEqual(signal.cycleCount, 1)
        _ = signal.consume(x: 0, y: 0.4, z: 0, time: 2.4)
        XCTAssertEqual(signal.cycleCount, 2)
    }

    func testInvalidVectorDoesNotResetCoherentAxisOrCreateCycle() {
        var signal = MotionSignal()
        _ = signal.consume(x: 0.4, y: 0, z: 0, time: 0)
        _ = signal.consume(x: -0.4, y: 0, z: 0, time: 0.4)
        XCTAssertFalse(signal.consume(x: 0, y: .nan, z: 0, time: 0.6))
        _ = signal.consume(x: 0.4, y: 0, z: 0, time: 0.8)
        XCTAssertEqual(signal.cycleCount, 1)
    }

    func testNoSamplesAreNotTreatedAsFreshStationarySamples() {
        var acquisition = MotionAcquisitionState()
        let start = Date(timeIntervalSince1970: 1000)
        _ = acquisition.start(at: start)
        XCTAssertFalse(acquisition.hasFreshSamples(at: start.addingTimeInterval(1)))
        XCTAssertTrue(acquisition.hasTimedOut(at: start.addingTimeInterval(3)))
    }

    func testStationarySamplesMaintainCoverageAndStallExpiresIt() {
        var acquisition = MotionAcquisitionState()
        let start = Date(timeIntervalSince1970: 1000)
        let generation = acquisition.start(at: start)
        XCTAssertTrue(acquisition.consume(timestamp: 100, deliveredAt: start.addingTimeInterval(0.05), generation: generation))
        XCTAssertEqual(acquisition.sampleCount, 1)
        XCTAssertTrue(acquisition.hasFreshSamples(at: start.addingTimeInterval(1)))
        XCTAssertTrue(acquisition.consume(timestamp: 101, deliveredAt: start.addingTimeInterval(1.05), generation: generation))
        XCTAssertEqual(acquisition.sampleCount, 2)
        XCTAssertFalse(acquisition.hasFreshSamples(at: start.addingTimeInterval(3.1)))
        XCTAssertTrue(acquisition.hasTimedOut(at: start.addingTimeInterval(3.1)))
    }

    func testOldGenerationCannotDeliverSamplesAfterRestartOrStop() {
        var acquisition = MotionAcquisitionState()
        let start = Date(timeIntervalSince1970: 1000)
        let previous = acquisition.start(at: start)
        let current = acquisition.start(at: start.addingTimeInterval(1))
        XCTAssertFalse(acquisition.accepts(generation: previous))
        XCTAssertFalse(acquisition.consume(timestamp: 100, deliveredAt: start.addingTimeInterval(1.05), generation: previous))
        XCTAssertEqual(acquisition.sampleCount, 0)
        XCTAssertTrue(acquisition.consume(timestamp: 101, deliveredAt: start.addingTimeInterval(1.05), generation: current))
        acquisition.stop()
        XCTAssertFalse(acquisition.accepts(generation: current))
        XCTAssertFalse(acquisition.consume(timestamp: 102, deliveredAt: start.addingTimeInterval(2.05), generation: current))
        XCTAssertFalse(acquisition.hasFreshSamples(at: start.addingTimeInterval(2.05)))
    }

    func testStaleDuplicateFutureAndReorderedSamplesDoNotRefreshCoverage() {
        var acquisition = MotionAcquisitionState()
        let start = Date(timeIntervalSince1970: 1000)
        let generation = acquisition.start(at: start)
        XCTAssertTrue(acquisition.consume(timestamp: 100, deliveredAt: start.addingTimeInterval(0.05), generation: generation))
        for (timestamp, elapsed) in [(100.0, 0.1), (99.0, 0.2), (Double.nan, 0.3), (200.0, 0.4), (100.1, 1.5)] {
            XCTAssertFalse(acquisition.consume(timestamp: timestamp, deliveredAt: start.addingTimeInterval(elapsed), generation: generation))
        }
        XCTAssertEqual(acquisition.sampleCount, 1)
        XCTAssertFalse(acquisition.hasFreshSamples(at: start.addingTimeInterval(2.1)))
    }

    func testLateFirstSampleAndWallClockRegressionAreRejected() {
        var acquisition = MotionAcquisitionState()
        let start = Date(timeIntervalSince1970: 1000)
        let generation = acquisition.start(at: start)
        XCTAssertFalse(acquisition.consume(timestamp: 100, deliveredAt: start.addingTimeInterval(4), generation: generation))
        XCTAssertFalse(acquisition.consume(timestamp: 100, deliveredAt: start.addingTimeInterval(-1), generation: generation))
        XCTAssertEqual(acquisition.sampleCount, 0)
    }
}
