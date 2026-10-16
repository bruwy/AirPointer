import CoreGraphics
import Foundation
import Testing
import Vision
@testable import AirPointer

@MainActor
@Suite("Left mouse button holds", .serialized)
struct LeftButtonBehaviorTests {
    @Test func indexPinchNeverPressesAMouseButton() {
        let h = ButtonHarness()
        h.feed(nil, 6)
        for _ in 0..<30 { h.feed(indexScrollHand().joints) }
        #expect(LeftButtonPose.analyze(indexScrollHand()).button == nil)
        #expect(h.output.desiredButton == nil)
    }

    @Test func closedNeutralCanArmWithoutIntermediateThumbJoints() {
        let h = ButtonHarness()
        var joints = buttonHand(nil, closed: true).joints
        joints[.thumbMP] = nil; joints[.thumbIP] = nil
        for _ in 0..<6 { h.feed(joints) }
        #expect(h.output.isReady)
        h.feed(.middle, 10)
        #expect(h.output.desiredButton == .middle)
    }

    @Test func closedThumbBetweenOldNeutralAndThumbUpBoundariesCanArmEveryButton() {
        for button in MouseButton.allCases {
            let h = ButtonHarness()
            let hand = closedHandWithThumbReach(1.0)
            #expect(MouseHandPose.analyze(hand).pose == .closed)
            #expect(LeftButtonPose.analyze(hand) == .neutral)
            for _ in 0..<8 { h.feed(hand.joints) }
            #expect(h.output.isReady)
            h.feed(button, 12)
            #expect(h.output.desiredButton == button)
        }
    }

    @Test func anOccludedExtendedThumbCannotArmARightButtonOnReturn() {
        let h = ButtonHarness()
        var joints = buttonHand(.right).joints
        joints[.thumbMP] = nil; joints[.thumbIP] = nil
        for _ in 0..<6 { h.feed(joints) }
        h.feed(.right, 30)
        #expect(h.output.desiredButton == nil)
        h.feed(nil, 6); h.feed(.right, 10)
        #expect(h.output.desiredButton == .right)
    }

    @Test func provenCurledBonesCanArmNeutralWithoutAFingertip() {
        for missing in [VNHumanHandPoseObservation.JointName.indexTip, .middleTip, .ringTip, .littleTip] {
            let h = ButtonHarness()
            var joints = buttonHand(nil, closed: true).joints
            joints[missing] = nil
            for _ in 0..<6 { h.feed(joints) }
            #expect(h.output.isReady)
            h.feed(.left, 10)
            #expect(h.output.desiredButton == .left)
        }
    }

    @Test func approvedButtonPosesRecognizeAcrossRotationAndScale() {
        for button in MouseButton.allCases {
            for angle in [-0.8, 0, 0.8] {
                for scale in [0.65, 1, 1.2] {
                    let source = buttonHand(button)
                    let wrist = source.wrist!
                    let joints = source.joints.mapValues { point in
                        let x = (point.x - wrist.x) * scale, y = (point.y - wrist.y) * scale
                        return CGPoint(x: 0.5 + x * cos(angle) - y * sin(angle),
                                       y: 0.4 + x * sin(angle) + y * cos(angle))
                    }
                    #expect(LeftButtonPose.analyze(buttonSnapshot(joints)) == .button(button))
                }
            }
        }
    }

    @Test func stablePoseHoldsOneDesiredButtonUntilRelease() {
        for button in MouseButton.allCases {
            let h = ButtonHarness()
            h.feed(nil, 6)
            #expect(h.output.isReady)
            h.feed(button, 3)
            #expect(h.output.desiredButton == nil)
            h.feed(button, 10)
            #expect(h.output.desiredButton == button)
            h.feed(button, 90)
            #expect(h.output.desiredButton == button)
            h.feed(nil, 1)
            #expect(h.output.desiredButton == button)
            h.feed(nil, 4)
            #expect(h.output.desiredButton == nil)
        }
    }

    @Test func directSwitchReleasesBeforeConfirmingTheNextButton() {
        for old in MouseButton.allCases {
            for new in MouseButton.allCases where new != old {
                let h = ButtonHarness()
                h.feed(nil, 6); h.feed(old, 10)
                #expect(h.output.desiredButton == old)
                h.feed(new, 1)
                #expect(h.output.desiredButton == nil)
                h.feed(new, 8)
                #expect(h.output.desiredButton == new)
            }
        }
    }

    @Test func pinchHysteresisPreventsChatterAndBriefNoiseCannotPress() {
        let h = ButtonHarness()
        h.feed(nil, 6)
        for _ in 0..<10 { h.feed(.middle, 1); h.feed(nil, 1) }
        #expect(h.output.desiredButton == nil)
        h.feed(.middle, 10)
        var hand = buttonHand(.middle).joints
        let middle = hand[.middleTip]!
        hand[.thumbTip] = CGPoint(x: middle.x - 0.36 * 0.15, y: middle.y)
        #expect(LeftButtonPose.analyze(buttonSnapshot(hand), holding: .middle) == .button(.middle))
        #expect(LeftButtonPose.analyze(buttonSnapshot(hand)) != .button(.middle))
        for _ in 0..<10 { h.feed(hand) }
        #expect(h.output.desiredButton == .middle)
    }

    @Test func lossAndInvalidFramesReleaseAndRequireNeutralBeforeRepress() {
        for fault in 0..<5 {
            let h = ButtonHarness()
            h.feed(nil, 6); h.feed(.middle, 10)
            #expect(h.output.desiredButton == .middle)
            switch fault {
            case 0: h.feedFrame(AirFrame(timestamp: h.date, hands: []))
            case 1:
                var joints = buttonHand(.middle).joints; joints[.thumbTip] = nil; h.feed(joints)
            case 2:
                var joints = buttonHand(.middle).joints; joints[.indexTip] = CGPoint(x: CGFloat.nan, y: 0.5); h.feed(joints)
            case 3: h.now += 0.6; h.feed(.middle, 1)
            default: h.now -= 0.04; h.feed(.middle, 1); h.now += 0.08
            }
            #expect(h.output.desiredButton == nil)
            h.feed(.middle, 30)
            #expect(h.output.desiredButton == nil)
            h.feed(nil, 6); h.feed(.middle, 10)
            #expect(h.output.desiredButton == .middle)
        }
    }

    @Test func resetAndRightHandNeverLeaveADesiredButtonHeld() {
        let h = ButtonHarness()
        h.feed(nil, 6); h.feed(.right, 10)
        h.engine.reset()
        h.feed(.right, 30)
        #expect(h.output.desiredButton == nil)
        h.feed(nil, 6)
        for _ in 0..<30 {
            let left = buttonHand(.left)
            let right = AirHandSnapshot(side: .right, joints: left.joints, wrist: left.wrist)
            h.feedFrame(AirFrame(timestamp: h.date, hands: [right]))
        }
        #expect(h.output.desiredButton == nil)
    }
}

@MainActor
final class ButtonHarness {
    let engine = LeftButtonEngine()
    var output = LeftButtonEngine.Output()
    var now: TimeInterval = 0
    var date: Date { Date(timeIntervalSinceReferenceDate: 10000 + now) }
    func feed(_ button: MouseButton?, _ count: Int) {
        for _ in 0..<count { feed(buttonHand(button).joints) }
    }
    func feed(_ joints: [VNHumanHandPoseObservation.JointName: CGPoint]) {
        feedFrame(AirFrame(timestamp: date, hands: [buttonSnapshot(joints)]))
    }
    func feedFrame(_ frame: AirFrame) {
        output = engine.process(frame: frame)
        now += 1.0 / 30
    }
}

func buttonSnapshot(_ joints: [VNHumanHandPoseObservation.JointName: CGPoint]) -> AirHandSnapshot {
    AirHandSnapshot(side: .left, joints: joints, wrist: joints[.wrist])
}

func buttonHand(_ button: MouseButton?, closed: Bool = false, wrist: CGPoint = CGPoint(x: 0.4, y: 0.3), indexPinch: Bool = false) -> AirHandSnapshot {
    let base = CGPoint(x: 0.4, y: 0.3)
    var joints: [VNHumanHandPoseObservation.JointName: CGPoint] = [.wrist: wrist]
    let names: [[VNHumanHandPoseObservation.JointName]] = [
        [.indexMCP, .indexPIP, .indexDIP, .indexTip], [.middleMCP, .middlePIP, .middleDIP, .middleTip],
        [.ringMCP, .ringPIP, .ringDIP, .ringTip], [.littleMCP, .littlePIP, .littleDIP, .littleTip]]
    for (i, names) in names.enumerated() {
        let curled = closed || button == .right || (button == .left && i == 2) || (button == .middle && i == 1) || (indexPinch && i == 0)
        let x = base.x + CGFloat(i) * 0.03 - 0.04
        let y = base.y + [0.13, 0.15, 0.14, 0.12][i]
        let heights: [CGFloat] = curled ? [0, 0.055, 0.005, 0.01] : [0, 0.07, 0.12, 0.17]
        for (name, height) in zip(names, heights) { joints[name] = CGPoint(x: x, y: y + height) }
    }
    joints[.thumbCMC] = CGPoint(x: 0.37, y: 0.32)
    joints[.thumbMP] = CGPoint(x: 0.35, y: 0.36)
    joints[.thumbIP] = CGPoint(x: 0.30, y: 0.405)
    joints[.thumbTip] = CGPoint(x: button == .right ? 0.23 : 0.26, y: button == .right ? 0.45 : 0.35)
    if closed && button == nil { joints[.thumbTip] = CGPoint(x: 0.31, y: 0.37) }
    if button == .left || button == .middle || indexPinch {
        let tip = joints[indexPinch ? .indexTip : (button == .left ? .ringTip : .middleTip)]!
        joints[.thumbTip] = CGPoint(x: tip.x - 0.01, y: tip.y)
    }
    joints[.wrist] = base
    return buttonSnapshot(joints.mapValues { CGPoint(x: $0.x + wrist.x - base.x, y: $0.y + wrist.y - base.y) })
}

func indexScrollHand(wrist: CGPoint = CGPoint(x: 0.4, y: 0.3)) -> AirHandSnapshot {
    buttonHand(nil, wrist: wrist, indexPinch: true)
}

func closedHandWithThumbReach(_ reach: CGFloat) -> AirHandSnapshot {
    var joints = buttonHand(nil, closed: true).joints
    let wrist = joints[.wrist]!, middle = joints[.middleMCP]!
    let scale = hypot(middle.x - wrist.x, middle.y - wrist.y)
    joints[.thumbTip] = CGPoint(x: wrist.x - scale * reach * cos(0.35),
                              y: wrist.y + scale * reach * sin(0.35))
    return buttonSnapshot(joints)
}
