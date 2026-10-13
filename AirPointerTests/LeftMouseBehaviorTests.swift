import AppKit
import Foundation
import Testing
import Vision
@testable import AirPointer

@MainActor
@Suite("Relative left trackpad and clicks", .serialized)
struct LeftMouseBehaviorTests {
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

    @Test func allProfilesMoveRelativelyAndBothClicksCommitOnRelease() {
        for profile in AirProfileKind.allCases {
            let h = MouseHarness(profile)
            h.feed(.closed, 10)
            h.move(0.08, frames: 20)
            #expect(!h.base.performer.moves.isEmpty)
            h.feed(.one, 15)
            #expect(h.clicks.isEmpty)
            h.feed(.closed, 8)
            h.feed(.two, 15)
            #expect(h.clicks == [false])
            h.feed(.closed, 8)
            #expect(h.clicks == [false, true])
            #expect(h.base.performer.keyCodes.isEmpty)
            #expect(h.base.performer.scrolls.isEmpty)
            #expect(!h.base.core.session.isRunning)
        }
    }

    @Test func rightHandCannotMoveOrClickMouse() {
        let h = MouseHarness()
        h.side = .right
        h.feed(.closed, 8); h.feed(.one, 15); h.feed(.closed, 8)
        h.feed(.two, 15); h.feed(.closed, 8)
        #expect(h.base.performer.moves.isEmpty)
        #expect(h.clicks.isEmpty)
    }

    @Test func bothHoldsProduceOneClickAndNeedNewGesture() {
        for pose in [MousePose.one, .two] {
            let h = MouseHarness()
            h.feed(.closed, 8); h.feed(pose, 120)
            #expect(h.clicks.isEmpty)
            h.feed(.closed, 60)
            #expect(h.clicks == [pose == .two])
            h.feed(pose, 15); h.feed(.closed, 8)
            #expect(h.clicks == [pose == .two, pose == .two])
        }
    }

    @Test func slowOneToTwoAndTwoToOneNeverEmitLeftClick() {
        for count in [1, 4, 30, 90] {
            let h = MouseHarness()
            h.feed(.closed, 8); h.feed(.one, count); h.feed(.two, 15)
            h.feed(.one, 12); h.feed(.closed, 8)
            #expect(h.clicks == [true])
        }
    }

    @Test func unconfirmedSecondFingerCannotFallBackToLeftClick() {
        let h = MouseHarness()
        h.feed(.closed, 8); h.feed(.one, 20); h.feed(.two, 1); h.feed(.closed, 8)
        #expect(h.clicks.isEmpty)
    }

    @Test func briefPosesCannotClickAndShortAmbiguityPausesEvidence() {
        for pose in [MousePose.one, .two] {
            let h = MouseHarness()
            h.feed(.closed, 8); h.feed(pose, 3); h.feed(.closed, 8)
            #expect(h.clicks.isEmpty)
        }
        let h = MouseHarness()
        h.feed(.closed, 8); h.feed(.one, 4)
        h.feed(.indexTransition, 1); h.feed(.one, 5); h.feed(.closed, 8)
        #expect(h.clicks == [false])
    }

    @Test func gradualIndexDescentRemainsAValidRelease() {
        let h = MouseHarness()
        h.feed(.closed, 8); h.feed(.one, 12); h.feed(.indexTransition, 8); h.feed(.closed, 8)
        #expect(h.clicks == [false])
    }

    @Test func openingToRepositionCancelsEvenConfirmedOneOrTwo() {
        for pose in [MousePose.one, .two] {
            let h = MouseHarness()
            h.feed(.closed, 8); h.feed(pose, 30); h.feed(.open, 10)
            h.wrist.x += 0.25; h.feed(.open, 10); h.feed(.closed, 10)
            #expect(h.clicks.isEmpty)
            #expect(h.base.performer.moves.isEmpty)
            h.move(0.02, frames: 12)
            #expect(!h.base.performer.moves.isEmpty)
        }
    }

    @Test func clickPosesParkCursorEvenWhenWristMoves() {
        let h = MouseHarness()
        h.feed(.closed, 8)
        for i in 0..<20 {
            h.wrist.x = 0.4 + CGFloat(i) * 0.003
            h.feed(.one, 1)
        }
        h.feed(.closed, 8)
        #expect(h.clicks == [false])
        #expect(h.base.performer.moves.isEmpty)
    }

    @Test func lossAndInvalidObservationsCancelAndNeverJumpOnReturn() {
        for fault in 0..<6 {
            let h = MouseHarness()
            h.feed(.closed, 8); h.feed(.one, 15)
            switch fault {
            case 0: h.empty()
            case 1:
                var j = mouseHand(.one).joints; j[.indexTip] = nil; h.feed(j)
            case 2:
                var j = mouseHand(.one).joints; j[.wrist] = CGPoint(x: CGFloat.nan, y: 0); h.feed(j)
            case 3: h.time -= 0.1; h.feed(.one, 1); h.time += 0.15
            case 4: h.time += 0.6; h.feed(.one, 1)
            default: h.time -= 1.0 / 30; h.feed(.one, 1)
            }
            h.wrist.x = 0.7
            h.feed(.one, 15); h.feed(.closed, 12)
            #expect(h.clicks.isEmpty)
            #expect(h.base.performer.moves.isEmpty)
            h.feed(.two, 12); h.feed(.closed, 8)
            #expect(h.clicks == [true])
        }
    }

    @Test func oldFrameStreamCannotRearmAfterRejection() {
        let h = MouseHarness()
        h.time = 20; h.feed(.closed, 8); h.feed(.one, 15)
        h.time = 0; h.feed(.closed, 8); h.feed(.two, 15); h.feed(.closed, 8)
        #expect(h.base.performer.actions.isEmpty)
    }

    @Test func modeSettingsStopAndPermissionsCancelPendingClicks() {
        for change in 0..<7 {
            let h = MouseHarness()
            h.feed(.closed, 8); h.feed(.one, 15)
            switch change {
            case 0: h.base.viewModel.setProfile(.call)
            case 1: h.base.viewModel.enableNext = false
            case 2: h.base.viewModel.mouseSensitivity = 2
            case 3: h.base.viewModel.stop(); h.base.viewModel.start()
            case 4:
                h.base.permissions.setAccessibility(.notTrusted); h.base.viewModel.refreshPermissionSnapshot()
                h.base.permissions.setAccessibility(.trusted); h.base.viewModel.refreshPermissionSnapshot()
            case 5:
                h.base.permissions.setCamera(.denied); h.base.viewModel.refreshPermissionSnapshot()
                h.base.permissions.setCamera(.authorized); h.base.viewModel.start()
            default: h.base.viewModel.resetContinuousGestures()
            }
            h.feed(.one, 10); h.feed(.closed, 8)
            #expect(h.clicks.isEmpty)
        }
    }

    @Test func permissionRevokedAtClickSubmissionBlocksIt() {
        for camera in [true, false] {
            let h = MouseHarness()
            h.feed(.closed, 8); h.feed(.two, 15)
            if camera { h.base.permissions.setCamera(.denied) }
            else { h.base.permissions.setAccessibility(.notTrusted) }
            h.feed(.closed, 8)
            #expect(h.base.performer.actions.isEmpty)
        }
    }

    @Test func failedSubmissionIsNotRetriedWhileHandRemainsClosed() {
        let h = MouseHarness()
        h.feed(.closed, 8); h.feed(.one, 15)
        h.base.performer.succeeds = false
        h.feed(.closed, 60)
        #expect(h.clicks == [false]) // one attempted event, reported as failure
        #expect(h.base.viewModel.commandStatus == .failed)
    }

    @Test func diagnosticsSendNothingAndKeepOnlyInMemoryTextAndCounts() {
        let h = MouseHarness()
        h.base.viewModel.diagnosticOnly = true
        h.base.viewModel.startFrameRecording()
        #expect(!h.base.viewModel.isRecordingFrames)
        h.feed(.closed, 8); h.move(0.05, frames: 20)
        h.feed(.one, 15); h.feed(.closed, 8); h.feed(.two, 15); h.feed(.closed, 8)
        #expect(h.base.viewModel.diagnosticLeftClicks == 1)
        #expect(h.base.viewModel.diagnosticRightClicks == 1)
        #expect(!h.base.viewModel.mouseEvidence.isEmpty)
        #expect(h.base.viewModel.commandStatus == .diagnostic)
        #expect(h.base.performer.actions.isEmpty)
        h.base.viewModel.diagnosticOnly = false
        h.feed(.two, 15); h.feed(.closed, 8)
        #expect(h.clicks.isEmpty)
        #expect(h.base.viewModel.diagnosticLeftClicks == 0)
    }

    @Test func diagnosticsAlsoSuppressRightHandCommandsAndScroll() {
        let h = OfflineHarness()
        h.viewModel.diagnosticOnly = true
        h.feed(doublePinchSequence(side: .right, startingAt: 0))
        h.feed(poseSequence([(.open, 8), (.fist, 25)], side: .right, startingAt: 1))
        #expect(h.performer.actions.isEmpty)
    }

    @Test func deepworkPinchParksMouseAndReleaseNeedsNeutralReanchor() {
        let h = MouseHarness(.deepwork)
        h.feed(.closed, 8)
        for i in 0..<25 {
            h.wrist.y = 0.3 + CGFloat(i) * 0.004
            h.feed(.pinch, 1)
        }
        #expect(!h.base.performer.scrolls.isEmpty)
        #expect(h.base.performer.moves.isEmpty && h.clicks.isEmpty)
        let count = h.base.performer.scrolls.count
        h.feed(.two, 15); h.feed(.closed, 10)
        #expect(h.clicks.isEmpty)
        #expect(h.base.performer.scrolls.count == count)
        #expect(h.base.performer.moves.isEmpty)
        h.feed(.two, 15); h.feed(.closed, 8)
        #expect(h.clicks == [true])
    }

    @Test func looseClosedHandWithThumbContactCannotScrollAndMoveTogether() throws {
        let h = MouseHarness(.deepwork)
        for i in 0..<30 {
            var j = mouseHand(.closed).joints.mapValues {
                CGPoint(x: 0.4 + ($0.x - 0.4) * 0.25 + CGFloat(i) * 0.002, y: $0.y)
            }
            j[.thumbTip] = j[.indexTip]
            #expect(MouseHandPose.analyze(snapshot(j)).pose == .closed)
            #expect(try #require(HandPoseMetrics.fistMetric(from: j)) > AppConfig.GestureTuning.fistThresholdOff)
            h.feed(j)
        }
        #expect(h.base.performer.scrolls.isEmpty)
        #expect(!h.base.performer.moves.isEmpty)
        #expect(h.clicks.isEmpty)
    }

    @Test func diagnosticModeSuppressesDeepworkScrollPerformer() {
        let h = MouseHarness(.deepwork)
        h.base.viewModel.diagnosticOnly = true
        for i in 0..<30 {
            h.wrist.y = 0.3 + CGFloat(i) * 0.003
            h.feed(.pinch, 1)
        }
        #expect(h.base.viewModel.commandStatus == .diagnostic)
        #expect(h.base.performer.actions.isEmpty)
    }

    @Test func disabledScrollAxesKeepRelativeMouseAndClicksAvailable() {
        let h = MouseHarness(.deepwork)
        h.base.viewModel.enableScroll = false; h.base.viewModel.enableScrub = false
        h.feed(.closed, 8); h.move(0.05, frames: 20)
        h.feed(.one, 15); h.feed(.closed, 8)
        #expect(h.clicks == [false])
        #expect(!h.base.performer.moves.isEmpty)
        #expect(h.base.performer.scrolls.isEmpty)
    }

    @Test func simultaneousLeftMouseAndRightPresentationGesturesStayIndependent() {
        let h = OfflineHarness()
        let right = poseSequence([(.open, 8), (.fist, 25), (.open, 8),
                                  (.pinch, 6), (.open, 4), (.pinch, 6), (.open, 4)], side: .right, startingAt: 0)
        for (i, f) in right.enumerated() {
            let left = mouseHand(i < 8 || i >= 25 ? .closed : .two)
            h.feed([AirFrame(timestamp: f.timestamp, hands: f.hands + [left])])
        }
        #expect(h.performer.clicks == [true])
        #expect(h.performer.keyCodes == [KeyCode.leftArrow, KeyCode.rightArrow])
    }

    @Test func leftPinkyCannotMute() {
        let h = OfflineHarness(); h.viewModel.setProfile(.call)
        h.feed((0..<30).map { jointsFrame(pinkyJoints(), at: Double($0) / 30, side: .left) })
        #expect(h.performer.keyCodes.isEmpty && h.performer.clicks.isEmpty)
        h.feed((0..<30).map { jointsFrame(pinkyJoints(), at: 1 + Double($0) / 30) })
        #expect(h.performer.keyCodes == [KeyCode.a])
    }

    @Test func queuedFrameBeforeProfileChangeIsDropped() async throws {
        let h = OfflineHarness()
        h.core.tracker.publish(["left": mouseHand(.two).joints])
        h.viewModel.setProfile(.call)
        try await Task.sleep(for: .milliseconds(60))
        #expect(h.performer.actions.isEmpty && h.viewModel.handJoints.isEmpty)
    }

    @Test func staleCoreObservationCancelsClick() async throws {
        let h = MouseHarness(); h.feed(.closed, 8); h.feed(.one, 15)
        h.base.core.tracker.publish(["left": mouseHand(.one).joints], at: Date().addingTimeInterval(-1))
        try await Task.sleep(for: .milliseconds(60))
        #expect(h.clicks.isEmpty)
        #expect(h.base.viewModel.pointerLocation == nil)
    }

    @Test func generatedClickPairsRemainBalancedWithoutPosting() throws {
        for right in [false, true] {
            let point = CGPoint(x: -130, y: 77)
            let pair = try #require(MouseController.clickEvents(buttonRight: right, at: point))
            #expect(pair.0.type == (right ? .rightMouseDown : .leftMouseDown))
            #expect(pair.1.type == (right ? .rightMouseUp : .leftMouseUp))
            #expect(pair.0.location == point && pair.1.location == point)
            #expect(pair.0.getIntegerValueField(.mouseEventClickState) == 1)
            #expect(pair.1.getIntegerValueField(.mouseEventClickState) == 1)
        }
    }
}

@MainActor
private final class MouseHarness {
    let base = OfflineHarness()
    var time = 0.0
    var wrist = CGPoint(x: 0.4, y: 0.3)
    var side = AirHandSide.left
    var clicks: [Bool] { base.performer.clicks }
    init(_ profile: AirProfileKind = .presentation) { base.viewModel.setProfile(profile) }
    func feed(_ pose: MousePose, _ count: Int) {
        for _ in 0..<count { feed(mouseHand(pose, wrist: wrist, side: side).joints) }
    }
    func feed(_ joints: [VNHumanHandPoseObservation.JointName: CGPoint]) {
        base.feed([AirFrame(timestamp: Foundation.Date(timeIntervalSinceReferenceDate: 10000 + time),
                            hands: [snapshot(joints, side: side)])])
        time += 1.0 / 30
    }
    func empty() {
        base.feed([AirFrame(timestamp: Date(timeIntervalSinceReferenceDate: 10000 + time), hands: [])])
        time += 1.0 / 30
    }
    func move(_ dx: CGFloat, frames: Int) {
        for _ in 0..<frames { wrist.x += dx / CGFloat(frames); feed(.closed, 1) }
    }
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
