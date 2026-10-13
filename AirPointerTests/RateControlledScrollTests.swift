import CoreGraphics
import Foundation
import Testing
import Vision
@testable import AirPointer

@MainActor
@Suite("Rate-controlled scroll")
struct RateControlledScrollTests {
    @Test func stationaryOffsetMaintainsSpeedIndependentOfFrameRate() {
        var totals: [Int32] = []
        for fps in [30, 60] {
            let h = ScrollFixture()
            #expect(h.feed(at: 0).isEmpty)
            var total: Int32 = 0
            for i in 1...fps {
                let movement = scrollPixels(h.feed(wrist: CGPoint(x: 0.5, y: 0.8),
                                                   at: Double(i) / Double(fps)))
                #expect(movement.x == 0)
                #expect(movement.y > 0)
                total += movement.y
            }
            #expect(abs(total - 900) <= 1)
            totals.append(total)
        }
        #expect(abs(totals[0] - totals[1]) <= 1)
    }

    @Test func returningToOriginStopsImmediatelyAndOppositeOffsetReverses() {
        let h = ScrollFixture()
        _ = h.feed(at: 0)
        #expect(scrollPixels(h.feed(wrist: CGPoint(x: 0.5, y: 0.7), at: 0.1)).y > 0)
        #expect(h.feed(at: 0.2).isEmpty)
        #expect(h.feed(at: 0.3).isEmpty)
        #expect(scrollPixels(h.feed(wrist: CGPoint(x: 0.5, y: 0.3), at: 0.4)).y < 0)
    }

    @Test func neutralZoneFiltersJitterAndAxesNeutralizeIndependently() {
        let h = ScrollFixture()
        _ = h.feed(at: 0)
        for i in 1...20 {
            let d: CGFloat = i.isMultiple(of: 2) ? 0.015 : -0.015
            #expect(h.feed(wrist: CGPoint(x: 0.5 + d, y: 0.5 - d), at: Double(i) / 30).isEmpty)
        }
        let diagonal = scrollPixels(h.feed(wrist: CGPoint(x: 0.7, y: 0.7), at: 0.7))
        #expect(diagonal.x > 0 && diagonal.y > 0)
        let vertical = scrollPixels(h.feed(wrist: CGPoint(x: 0.5, y: 0.7), at: 0.8))
        #expect(vertical.x == 0 && vertical.y > 0)
    }

    @Test func speedAndEventSizeAreBoundedForLargeDisplacement() {
        let h = ScrollFixture()
        _ = h.feed(wrist: CGPoint(x: 0.01, y: 0.01), at: 0)
        for i in 1...10 {
            let p = scrollPixels(h.feed(wrist: CGPoint(x: 0.99, y: 0.99), at: Double(i) * 0.2))
            #expect(p.x > 0 && p.x <= 60)
            #expect(p.y > 0 && p.y <= 60)
        }
    }

    @Test func lowSpeedAccumulatesFractionsWithoutAStoppedTail() {
        let h = ScrollFixture()
        _ = h.feed(at: 0)
        var total: Int32 = 0
        for i in 1...60 {
            total += scrollPixels(h.feed(wrist: CGPoint(x: 0.5, y: 0.521), at: Double(i) / 30)).y
        }
        #expect(total >= 9 && total <= 10)
        #expect(h.feed(at: 2.1).isEmpty)
        #expect(h.feed(at: 2.2).isEmpty)
    }

    @Test func releaseLossChangedGestureAndInvalidJointsCancelAndReanchor() {
        for invalid in 0..<7 {
            let h = ScrollFixture()
            _ = h.feed(at: 0)
            #expect(scrollPixels(h.feed(wrist: CGPoint(x: 0.5, y: 0.7), at: 0.1)).y > 0)
            var joints = scrollJoints(pose: .pinch, wrist: CGPoint(x: 0.5, y: 0.7))
            let stopped: [DeepworkEngine.Action]
            switch invalid {
            case 0: stopped = h.feed(wrist: CGPoint(x: 0.5, y: 0.7), at: 0.2, pinching: false)
            case 1: stopped = h.feed(wrist: nil, at: 0.2)
            case 2: stopped = h.feed(wrist: CGPoint(x: 0.5, y: 0.7), at: 0.2, pose: .fist)
            case 3: stopped = h.feed(wrist: CGPoint(x: 0.5, y: 0.7), at: 0.2, pose: .open)
            case 4:
                joints[.thumbTip] = nil
                stopped = h.feed(wrist: CGPoint(x: 0.5, y: 0.7), at: 0.2, joints: joints)
            case 5: stopped = h.feed(wrist: CGPoint(x: .nan, y: 0.7), at: 0.2)
            default: stopped = h.feed(wrist: CGPoint(x: 1.1, y: 0.7), at: 0.2)
            }
            #expect(stopped.isEmpty)
            #expect(h.feed(wrist: CGPoint(x: 0.5, y: 0.7), at: 0.3).isEmpty)
            #expect(h.feed(wrist: CGPoint(x: 0.5, y: 0.7), at: 0.4).isEmpty)
        }
    }

    @Test func duplicateReversedOrGappedTimestampCannotReplayVelocity() {
        for timestamp in [0.1, 0.05, 0.6] {
            let h = ScrollFixture()
            _ = h.feed(at: 0)
            #expect(scrollPixels(h.feed(wrist: CGPoint(x: 0.5, y: 0.7), at: 0.1)).y > 0)
            #expect(h.feed(wrist: CGPoint(x: 0.5, y: 0.7), at: timestamp).isEmpty)
            #expect(h.feed(wrist: CGPoint(x: 0.5, y: 0.7), at: 0.7).isEmpty)
            #expect(h.feed(wrist: CGPoint(x: 0.5, y: 0.7), at: 0.733).isEmpty)
        }
    }

    @Test func rightHandPinchCannotProduceScroll() {
        let h = ScrollFixture()
        for i in 0..<30 {
            #expect(h.feed(wrist: CGPoint(x: 0.5, y: 0.5 + CGFloat(i) * 0.01),
                           at: Double(i) / 30, side: .right).isEmpty)
        }
    }
}

@MainActor
private struct ScrollFixture {
    let engine = DeepworkEngine()

    func feed(wrist: CGPoint? = CGPoint(x: 0.5, y: 0.5), at timestamp: Double,
              pinching: Bool = true, pose: SyntheticHandPose = .pinch,
              joints: [VNHumanHandPoseObservation.JointName: CGPoint]? = nil,
              side: AirHandSide = .left) -> [DeepworkEngine.Action] {
        let hands = wrist.map { point in
            [AirHandSnapshot(side: side, joints: joints ?? scrollJoints(pose: pose, wrist: point), wrist: point)]
        } ?? []
        return engine.process(frame: AirFrame(timestamp: time(timestamp), hands: hands),
                              leftState: (pinching, false, 0.08), rightState: (false, false, 1))
    }
}

private func scrollJoints(pose: SyntheticHandPose, wrist: CGPoint) -> [VNHumanHandPoseObservation.JointName: CGPoint] {
    syntheticJoints(for: pose).mapValues {
        CGPoint(x: $0.x * 0.1 + wrist.x, y: $0.y * 0.1 + wrist.y)
    }
}

private func scrollPixels(_ actions: [DeepworkEngine.Action]) -> (x: Int32, y: Int32) {
    var x: Int32 = 0
    var y: Int32 = 0
    for action in actions {
        switch action {
        case .scroll(let dx, let dy): x += dx; y += dy
        case .scrub(let dx): x += dx
        default: Issue.record("Scroll fixtures must not emit other commands")
        }
    }
    return (x, y)
}
