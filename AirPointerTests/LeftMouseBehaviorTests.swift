import AppKit
import Foundation
import Testing
import Vision
@testable import AirPointer

@MainActor
@Suite("Left mouse movement, buttons and holds", .serialized)
struct LeftMouseBehaviorTests {
    @Test func allProfilesMoveAndHoldEachButtonForDragging() {
        for profile in AirProfileKind.allCases {
            for button in MouseButton.allCases {
                let h = HoldMouseHarness(profile)
                h.feed(.closed, 8); h.feed(.button(button), 12)
                #expect(h.base.performer.buttonDowns == [button])
                #expect(h.base.performer.buttonUps.isEmpty)
                h.move(.button(button), by: 0.04, frames: 12)
                #expect(!h.base.performer.drags.isEmpty)
                #expect(h.base.performer.drags.allSatisfy { $0.button == button })
                h.feed(.closed, 6)
                #expect(h.base.performer.buttonUps == [button])
                #expect(h.base.performer.scrolls.isEmpty)
                #expect(h.base.performer.keyCodes.isEmpty)
                #expect(!h.base.core.session.isRunning)
            }
        }
    }

    @Test func changingFingersAtFixedWristDoesNotMoveOrReanchorTheCursor() {
        let h = HoldMouseHarness()
        h.feed(.closed, 8)
        for button in MouseButton.allCases { h.feed(.button(button), 12); h.feed(.closed, 6) }
        #expect(h.base.performer.moves.isEmpty && h.base.performer.drags.isEmpty)
        #expect(h.base.performer.buttonDowns == MouseButton.allCases)
        #expect(h.base.performer.buttonUps == MouseButton.allCases)
    }

    @Test func cursorKeepsMovingWhileTheButtonFormsAndWhileItIsHeld() {
        let h = HoldMouseHarness()
        h.feed(.closed, 8)
        h.move(.button(.middle), by: 0.05, frames: 18)
        #expect(!h.base.performer.moves.isEmpty)
        #expect(!h.base.performer.drags.isEmpty)
        #expect(h.base.performer.buttonDowns == [.middle])
        h.feed(.button(.middle), 60)
        #expect(h.base.performer.buttonDowns == [.middle])
        #expect(h.base.viewModel.cursorFeedback.phase == .pressed)
        #expect(h.base.viewModel.cursorFeedback.commandID == 1)
    }

    @Test func indexPinchAndDragRemainScrollWithoutPressingAnyButton() {
        let h = HoldMouseHarness(.deepwork)
        h.feed(.closed, 8)
        h.move(.scroll, by: 0.08, frames: 25)
        #expect(!h.base.performer.scrolls.isEmpty)
        #expect(h.base.performer.buttonDowns.isEmpty)
        #expect(h.base.performer.moves.isEmpty && h.base.performer.drags.isEmpty)
    }

    @Test func everyButtonCanArmAfterClosedMovementWithOccludedNeutralThumbBones() {
        for button in MouseButton.allCases {
            let h = HoldMouseHarness()
            var neutral = buttonHand(nil, closed: true).joints
            neutral[.thumbMP] = nil; neutral[.thumbIP] = nil
            for _ in 0..<8 { h.feed(neutral) }
            h.feed(.button(button), 12)
            #expect(h.base.performer.buttonDowns == [button])
            h.feed(.closed, 6)
            #expect(h.base.performer.buttonUps == [button])
        }
    }

    @Test func fullOpenClutchRearmsButtonsAcrossFramesBeforeClosingToMove() {
        for profile in AirProfileKind.allCases {
            for button in MouseButton.allCases {
                let h = HoldMouseHarness(profile)
                // This complete closed pose can move the pointer but is outside
                // the relaxed-thumb radial gate. Opening must be a usable neutral.
                let neutral = closedHandWithThumbReach(1.14)
                #expect(MouseHandPose.analyze(neutral).pose == .closed)
                #expect(LeftButtonPose.analyze(neutral).button == nil)
                for _ in 0..<8 { h.feed(neutral.joints) }
                h.feed(.open, 12)
                for _ in 0..<8 { h.feed(neutral.joints) }
                h.feed(.button(button), 12)
                #expect(h.base.performer.buttonDowns == [button])
                #expect(h.base.performer.moves.isEmpty && h.base.performer.drags.isEmpty)
                h.feed(.open, 1)
                #expect(h.base.performer.buttonUps == [button])
            }
        }
    }

    @Test func oneOpenFrameReleasesImmediatelyAndCannotResurrectTheOldHold() {
        let h = HoldMouseHarness()
        h.feed(.closed, 8); h.feed(.button(.left), 12)
        h.feed(.open, 1)
        #expect(h.base.performer.buttonUps == [.left])
        h.feed(.closed, 1); h.feed(.button(.left), 20)
        #expect(h.base.performer.buttonDowns == [.left])
        h.feed(.closed, 8); h.feed(.button(.left), 12)
        #expect(h.base.performer.buttonDowns == [.left, .left])
    }

    @Test func enteringIndexScrollReleasesTheHeldButtonBeforeScrolling() {
        for button in MouseButton.allCases {
            let h = HoldMouseHarness(.deepwork)
            h.feed(.closed, 8); h.feed(.button(button), 12)
            h.move(.scroll, by: 0.08, frames: 25)
            #expect(h.base.performer.buttonDowns == [button])
            #expect(h.base.performer.buttonUps == [button])
            #expect(!h.base.performer.scrolls.isEmpty)
            if let up = h.base.performer.actions.firstIndex(where: {
                if case .mouseButton(_, pressed: false) = $0 { return true }; return false
            }), let scroll = h.base.performer.actions.firstIndex(where: {
                if case .scroll = $0 { return true }; return false
            }) { #expect(up < scroll) }
            else { Issue.record("Expected release before scroll") }
        }
    }

    @Test func openingPalmReleasesImmediatelyAndRepositionNeverJumps() {
        let h = HoldMouseHarness()
        h.feed(.closed, 8); h.feed(.button(.middle), 12)
        h.feed(.open, 1)
        #expect(h.base.performer.buttonUps == [.middle])
        #expect(h.base.viewModel.cursorFeedback.phase == .hidden)
        h.wrist.x += 0.22; h.feed(.open, 10); h.feed(.closed, 8)
        #expect(h.base.performer.moves.isEmpty && h.base.performer.drags.isEmpty)
        h.move(.closed, by: 0.02, frames: 10)
        #expect(!h.base.performer.moves.isEmpty)
    }

    @Test func directSwitchNeverHoldsTwoButtonsAndKeepsTheWristAnchor() {
        let h = HoldMouseHarness()
        h.feed(.closed, 8); h.feed(.button(.middle), 12)
        h.feed(.button(.right), 1)
        #expect(h.base.performer.buttonDowns == [.middle])
        #expect(h.base.performer.buttonUps == [.middle])
        h.feed(.button(.right), 10)
        #expect(h.base.performer.buttonDowns == [.middle, .right])
        #expect(h.base.performer.moves.isEmpty && h.base.performer.drags.isEmpty)
    }

    @Test func lossBadTimeJointsAndTrackingJumpsReleaseWithoutRepressing() {
        for fault in 0..<7 {
            let h = HoldMouseHarness()
            h.feed(.closed, 8); h.feed(.button(.middle), 12)
            switch fault {
            case 0: h.empty()
            case 1:
                var joints = buttonHand(.middle).joints; joints[.wrist] = nil; h.feed(joints)
            case 2:
                var joints = buttonHand(.middle).joints; joints[.indexTip] = CGPoint(x: CGFloat.nan, y: 0.5); h.feed(joints)
            case 3: h.now -= 0.1; h.feed(.button(.middle), 1); h.now += 0.15
            case 4: h.now += 0.6; h.feed(.button(.middle), 1)
            case 5: h.wrist.x += 0.2; h.feed(.button(.middle), 1)
            default:
                let wrist = h.wrist
                h.feed(buttonHand(.middle).joints.mapValues {
                    CGPoint(x: wrist.x + ($0.x - wrist.x) * 1.8, y: wrist.y + ($0.y - wrist.y) * 1.8)
                })
            }
            #expect(h.base.performer.buttonUps == [.middle])
            h.feed(.button(.middle), 20)
            #expect(h.base.performer.buttonDowns == [.middle])
            h.feed(.closed, 8); h.feed(.button(.right), 12)
            #expect(h.base.performer.buttonDowns == [.middle, .right])
        }
    }

    @Test func settingsStopPermissionsAndWatchdogReleaseAllOwnedButtons() {
        for change in 0..<10 {
            let h = HoldMouseHarness()
            h.feed(.closed, 8); h.feed(.button(.right), 12)
            switch change {
            case 0: h.base.viewModel.setProfile(.call)
            case 1: h.base.viewModel.stop()
            case 2: h.base.viewModel.diagnosticOnly = true
            case 3:
                h.base.permissions.setCamera(.denied); h.base.viewModel.refreshPermissionSnapshot()
            case 4:
                h.base.permissions.setAccessibility(.notTrusted); h.base.viewModel.refreshPermissionSnapshot()
            case 5: h.base.viewModel.mouseSensitivity = 2
            case 6: h.base.viewModel.enableNext = false
            case 7: h.base.viewModel.resetContinuousGestures()
            case 8: h.base.viewModel.expireTrackingState(at: h.base.feedbackClock.now + 0.26)
            default:
                h.base.viewModel.cursorFeedbackEnabled = false
                h.base.viewModel.expireTrackingState(at: h.base.feedbackClock.now + 0.26)
            }
            #expect(h.base.performer.buttonUps == [.right])
            #expect(h.base.viewModel.cursorFeedback.phase == .hidden)
            h.feed(.button(.right), 30)
            #expect(h.base.performer.buttonDowns == [.right])
        }
    }

    @Test func turningOffHaloDoesNotChangeTheHoldOrDragging() {
        let h = HoldMouseHarness()
        h.feed(.closed, 8); h.feed(.button(.middle), 12)
        h.base.viewModel.cursorFeedbackEnabled = false
        #expect(h.base.performer.buttonUps.isEmpty)
        h.move(.button(.middle), by: 0.03, frames: 10)
        #expect(!h.base.performer.drags.isEmpty)
        #expect(h.base.viewModel.cursorFeedback.phase == .hidden)
        h.feed(.closed, 6)
        #expect(h.base.performer.buttonUps == [.middle])
    }

    @Test func watchdogNoticesPermissionRevocationWhileTheHandIsStationary() {
        for camera in [false, true] {
            let h = HoldMouseHarness()
            h.feed(.closed, 8); h.feed(.button(.middle), 12)
            if camera { h.base.permissions.setCamera(.denied) }
            else { h.base.permissions.setAccessibility(.notTrusted) }
            h.base.viewModel.expireTrackingState()
            #expect(h.base.performer.buttonUps == [.middle])
            #expect(h.base.viewModel.cursorFeedback.phase == .hidden)
        }
    }

    @Test func diagnosticsCountThreeButtonsWithoutSendingEvents() {
        let h = HoldMouseHarness()
        h.base.viewModel.diagnosticOnly = true
        h.feed(.closed, 8)
        for button in MouseButton.allCases { h.feed(.button(button), 12); h.feed(.closed, 6) }
        #expect(h.base.viewModel.diagnosticLeftClicks == 1)
        #expect(h.base.viewModel.diagnosticMiddleClicks == 1)
        #expect(h.base.viewModel.diagnosticRightClicks == 1)
        #expect(h.base.performer.actions.isEmpty)
        #expect(h.base.viewModel.cursorFeedback.phase == .hidden)
    }

    @Test func permissionDeniedBeforePressCannotSendDownOrUnownedUp() {
        for camera in [false, true] {
            let h = HoldMouseHarness()
            h.feed(.closed, 8)
            if camera { h.base.permissions.setCamera(.denied) }
            else { h.base.permissions.setAccessibility(.notTrusted) }
            h.feed(.button(.middle), 12)
            #expect(h.base.performer.actions.isEmpty)
            #expect(h.base.viewModel.cursorFeedback.phase == .hidden)
        }
    }

    @Test func failedDownAttemptsCleanupAndCannotRepeatWithoutNeutral() {
        let h = HoldMouseHarness()
        defer { h.base.performer.onPerform = nil }
        h.feed(.closed, 8)
        h.base.performer.onPerform = { action in
            if case .mouseButton(_, let pressed) = action { h.base.performer.succeeds = !pressed }
        }
        h.feed(.button(.middle), 60)
        #expect(h.base.performer.buttonDowns == [.middle])
        #expect(h.base.performer.buttonUps == [.middle])
        #expect(h.base.viewModel.commandStatus == .failed)
    }

    @Test func failedUpBlocksReplacementAndCanBeRetriedAfterStop() {
        let h = HoldMouseHarness()
        h.feed(.closed, 8); h.feed(.button(.middle), 12)
        h.base.performer.succeeds = false
        h.base.viewModel.stop()
        h.base.viewModel.start()
        h.feed(.button(.right), 12)
        #expect(h.base.performer.buttonDowns == [.middle])
        h.base.performer.succeeds = true
        h.base.viewModel.expireTrackingState()
        h.base.viewModel.start()
        h.feed(.closed, 8); h.feed(.button(.right), 12)
        #expect(h.base.performer.buttonDowns == [.middle, .right])
    }

    @Test func stopDuringDownReleasesItWithoutLeavingAnOwnedButton() {
        let h = HoldMouseHarness()
        defer { h.base.performer.onPerform = nil }
        h.feed(.closed, 8)
        h.base.performer.onPerform = { action in
            if case .mouseButton(_, pressed: true) = action { h.base.viewModel.stop() }
        }
        h.feed(.button(.middle), 60)
        #expect(h.base.performer.buttonDowns == [.middle])
        #expect(h.base.performer.buttonUps == [.middle])
        #expect(h.base.viewModel.cursorFeedback.phase == .hidden)
    }

    @Test func rightLaserDoesNotMoveMouseAndDoesNotHideAHeldButton() {
        let h = HoldMouseHarness(.deepwork)
        h.feed(.closed, 8)
        for _ in 0..<25 { h.feed(.button(.middle), 1, laser: true) }
        #expect(h.base.viewModel.pointerLocation != nil)
        #expect(h.base.performer.moves.isEmpty && h.base.performer.drags.isEmpty)
        #expect(h.base.performer.buttonDowns == [.middle])
        #expect(h.base.viewModel.cursorFeedback.phase == .pressed)
        #expect(h.base.viewModel.cursorFeedback.pressedButton == .middle)
        h.feed(.closed, 6, laser: true)
        #expect(h.base.performer.buttonUps == [.middle])
        #expect(h.base.viewModel.cursorFeedback.phase == .hidden)
    }

    @Test func rightHandCannotOwnMouseButtonsOrMovement() {
        let h = HoldMouseHarness()
        h.side = .right
        h.feed(.closed, 8)
        for button in MouseButton.allCases { h.move(.button(button), by: 0.02, frames: 12) }
        #expect(h.base.performer.buttonDowns.isEmpty)
        #expect(h.base.performer.moves.isEmpty && h.base.performer.drags.isEmpty)
    }

    @Test func ownFingerBonesRecognizeRotationsScalesAndNaturalThumb() {
        for angle in [-1.2, -0.5, 0.0, 0.8, 1.5] {
            for scale in [0.65, 1.0, 1.3] {
                for (pose, expected) in [(MousePose.closed, MouseHandPose.Pose.closed), (.one, .one), (.two, .two), (.open, .clutch)] {
                    for thumb in [false, true] {
                        let hand = transformed(mouseHand(pose, thumbUp: thumb), angle: angle, scale: scale)
                        #expect(MouseHandPose.analyze(hand).pose == expected)
                    }
                }
            }
        }
    }

    @Test func curledFingerTipsCanBeOccludedWhenVisibleJointsProveCurl() {
        var hand = mouseHand(.one)
        var joints = hand.joints
        joints[.ringTip] = nil; joints[.littleTip] = nil
        hand = snapshot(joints)
        #expect(MouseHandPose.analyze(hand).pose == .one)
        joints[.indexTip] = nil
        #expect(MouseHandPose.analyze(snapshot(joints)).pose == .unknown)
        joints = mouseHand(.two).joints
        joints[.middleTip] = nil
        #expect(MouseHandPose.analyze(snapshot(joints)).pose == .unknown)
    }

    @Test func missingPIPUsesConservativeFallbackAndUnknownsNeverMeanCurled() {
        var joints = mouseHand(.one).joints
        joints[.indexPIP] = nil
        #expect(MouseHandPose.analyze(snapshot(joints)).pose == .one)
        joints[.ringTip] = nil; joints[.ringPIP] = nil
        #expect(MouseHandPose.analyze(snapshot(joints)).pose == .unknown)
        joints = mouseHand(.one).joints
        joints[.ringTip] = CGPoint(x: CGFloat.nan, y: 0.5)
        #expect(MouseHandPose.analyze(snapshot(joints)).pose == .unknown)
    }

    @Test func threeExtendedFingersClutchEvenWithFourthMissing() {
        var joints = mouseHand(.open).joints
        joints[.littleTip] = nil; joints[.littlePIP] = nil
        #expect(MouseHandPose.analyze(snapshot(joints)).pose == .clutch)
    }

}

@MainActor
private final class HoldMouseHarness {
    let base = OfflineHarness()
    var now: TimeInterval = 0
    var wrist = CGPoint(x: 0.4, y: 0.3)
    var side = AirHandSide.left
    init(_ profile: AirProfileKind = .presentation) { base.viewModel.setProfile(profile) }
    func feed(_ pose: HoldPose, _ count: Int, laser: Bool = false) {
        for _ in 0..<count {
            let hand: AirHandSnapshot
            switch pose {
            case .closed: hand = buttonHand(nil, closed: true, wrist: wrist)
            case .open: hand = buttonHand(nil, wrist: wrist)
            case .button(let button): hand = buttonHand(button, wrist: wrist)
            case .scroll: hand = indexScrollHand(wrist: wrist)
            }
            var hands = [AirHandSnapshot(side: side, joints: hand.joints, wrist: hand.wrist)]
            if laser { hands.append(rightLaserHand()) }
            feedFrame(hands)
        }
    }
    func feed(_ joints: [VNHumanHandPoseObservation.JointName: CGPoint]) {
        feedFrame([AirHandSnapshot(side: side, joints: joints, wrist: joints[.wrist])])
    }
    private func feedFrame(_ hands: [AirHandSnapshot]) {
        base.feed([AirFrame(timestamp: Date(timeIntervalSinceReferenceDate: 10000 + now), hands: hands)])
        now += 1.0 / 30
    }
    func empty() { feedFrame([]) }
    func move(_ pose: HoldPose, by distance: CGFloat, frames: Int) {
        for _ in 0..<frames { wrist.x += distance / CGFloat(frames); feed(pose, 1) }
    }
}
private enum HoldPose { case closed, open, scroll, button(MouseButton) }

func rightLaserHand() -> AirHandSnapshot {
    var joints = buttonHand(nil, closed: true).joints
    joints[.indexTip] = CGPoint(x: 0.36, y: 0.60)
    let fingers: [(VNHumanHandPoseObservation.JointName, VNHumanHandPoseObservation.JointName)] = [
        (.middleTip, .middleMCP), (.ringTip, .ringMCP), (.littleTip, .littleMCP)]
    for (tip, knuckle) in fingers {
        joints[tip] = joints[knuckle]
    }
    return AirHandSnapshot(side: .right, joints: joints, wrist: joints[.wrist])
}
private enum MousePose { case closed, one, two, open, indexTransition, pinch }
private func snapshot(_ joints: [VNHumanHandPoseObservation.JointName: CGPoint], side: AirHandSide = .left) -> AirHandSnapshot {
    AirHandSnapshot(side: side, joints: joints, wrist: joints[.wrist])
}
private func mouseHand(_ pose: MousePose, wrist: CGPoint = CGPoint(x: 0.4, y: 0.3),
                       side: AirHandSide = .left, thumbUp: Bool = false) -> AirHandSnapshot {
    var j: [VNHumanHandPoseObservation.JointName: CGPoint] = [.wrist: wrist]
    let names: [[VNHumanHandPoseObservation.JointName]] = [
        [.indexMCP, .indexPIP, .indexDIP, .indexTip], [.middleMCP, .middlePIP, .middleDIP, .middleTip],
        [.ringMCP, .ringPIP, .ringDIP, .ringTip], [.littleMCP, .littlePIP, .littleDIP, .littleTip]]
    for (i, names) in names.enumerated() {
        let x = wrist.x + CGFloat(i) * 0.03 - 0.04
        let y = wrist.y + [0.13, 0.15, 0.14, 0.12][i]
        let up = pose == .open || (pose == .one && i == 0) || (pose == .two && i < 2) || (pose == .pinch && i > 0)
        let size: CGFloat = i == 3 ? 0.8 : 1
        let heights: [CGFloat] = up ? [0, 0.07 * size, 0.12 * size, 0.17 * size] : [0, 0.055, 0.005, 0.01]
        for (name, height) in zip(names, heights) { j[name] = CGPoint(x: x, y: y + height) }
    }
    j[.thumbTip] = CGPoint(x: wrist.x - 0.12, y: wrist.y + (thumbUp ? 0.25 : 0.07))
    if pose == .pinch { j[.thumbTip] = j[.indexTip].map { CGPoint(x: $0.x + 0.01, y: $0.y) } }
    if pose == .indexTransition { j[.indexPIP] = nil; j[.indexTip] = CGPoint(x: wrist.x - 0.04, y: wrist.y + 0.19) }
    return snapshot(j, side: side)
}
private func transformed(_ hand: AirHandSnapshot, angle: Double, scale: Double) -> AirHandSnapshot {
    let center = hand.wrist!
    return snapshot(hand.joints.mapValues { p in
        let dx = (p.x - center.x) * scale, dy = (p.y - center.y) * scale
        return CGPoint(x: 0.5 + dx * cos(angle) - dy * sin(angle), y: 0.5 + dx * sin(angle) + dy * cos(angle))
    })
}

@MainActor
@Suite("Native Vision button landmarks", .serialized)
struct NativeVisionButtonRegressionTests {
    @Test func nativeMiddleAndRightReferenceLandmarksHoldDragAndReleaseInEveryProfile() {
        for profile in AirProfileKind.allCases {
            for (button, hand) in [(MouseButton.middle, nativeMiddleButtonHand()), (.right, nativeRightButtonHand())] {
                let h = HoldMouseHarness(profile)
                let neutral = neutralHandForNativeReference(hand)
                for _ in 0..<8 { h.feed(neutral.joints) }
                #expect(LeftButtonPose.analyze(hand) == .button(button))
                for _ in 0..<20 { h.feed(hand.joints) }
                #expect(h.base.performer.buttonDowns == [button])
                #expect(h.base.viewModel.mouseButtonStatus.contains("held"))
                #expect(h.base.viewModel.mouseButtonStatus.contains("posted: \(button.title)"))
                for frame in 1...12 {
                    h.feed(hand.joints.mapValues { CGPoint(x: $0.x + Double(frame) * 0.001, y: $0.y) })
                }
                #expect(!h.base.performer.drags.isEmpty)
                #expect(h.base.performer.drags.allSatisfy { $0.button == button })
                for _ in 0..<6 { h.feed(neutral.joints) }
                #expect(h.base.performer.buttonUps == [button])
                #expect(h.base.performer.scrolls.isEmpty)
            }
        }
    }

    @Test func nativeIndexReferenceRemainsScrollAndNeverPressesAButton() {
        let hand = nativeIndexScrollHand()
        let h = HoldMouseHarness(.deepwork)
        for _ in 0..<8 { h.feed(neutralHandForNativeReference(hand).joints) }
        for frame in 0..<30 {
            h.feed(hand.joints.mapValues { CGPoint(x: $0.x, y: $0.y + Double(frame) * 0.002) })
        }
        #expect(h.base.performer.buttonDowns.isEmpty)
        #expect(!h.base.performer.scrolls.isEmpty)
        #expect(h.base.performer.moves.isEmpty && h.base.performer.drags.isEmpty)
        #expect(h.base.viewModel.mouseButtonStatus.contains("index scroll"))
    }

    @Test func ringContactAtTheMeasuredVisionDistanceHoldsWithoutStealingIndexScroll() {
        for profile in AirProfileKind.allCases {
            let h = HoldMouseHarness(profile)
            h.feed(.closed, 8)
            var hand = buttonHand(.left).joints
            let ring = hand[.ringTip]!
            let scale = MouseHandPose.analyze(buttonSnapshot(hand)).scale!
            hand[.thumbTip] = CGPoint(x: ring.x - scale * 0.27, y: ring.y)
            #expect(LeftButtonPose.analyze(buttonSnapshot(hand)) == .button(.left))
            for _ in 0..<20 { h.feed(hand) }
            #expect(h.base.performer.buttonDowns == [.left])
            h.feed(.closed, 6)
            #expect(h.base.performer.buttonUps == [.left])
        }
    }

    @Test func contactStillRequiresSeparationFromIndexAndOtherButtonFinger() {
        for button in [MouseButton.left, .middle] {
            var hand = buttonHand(button).joints
            hand[.indexTip] = hand[.thumbTip]
            #expect(LeftButtonPose.analyze(buttonSnapshot(hand)).button == nil)
            hand = buttonHand(button).joints
            hand[button == .left ? .middleTip : .ringTip] = hand[.thumbTip]
            #expect(LeftButtonPose.analyze(buttonSnapshot(hand)).button == nil)
        }
    }
}
