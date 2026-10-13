import AppKit
import Combine
import Foundation
import Testing
import Vision
@testable import AirPointer

@MainActor
@Suite("Offline command pipeline", .serialized)
struct OfflineCommandPipelineTests {
    @Test func identicalObservationsReachAirCore() async throws {
        let tracker = HandTracker(configuresCamera: false)
        let core = AirCore(tracker: tracker)
        let delegate = CountingFrameDelegate()
        core.delegate = delegate
        let joints = ["right": pinkyJoints()]
        for _ in 0..<3 { tracker.publish(joints) }
        try await Task.sleep(for: .milliseconds(100))
        #expect(delegate.frames.count == 3)
        #expect(!tracker.session.isRunning)
    }

    @Test func presentationUsesRightDoublePinchAndRightFistWithLeftHandFree() {
        let h = OfflineHarness()
        h.feed(doublePinchSequence(side: .right, startingAt: 0))
        #expect(h.performer.keyCodes == [KeyCode.rightArrow])
        h.feed(doublePinchSequence(side: .left, startingAt: 1))
        h.feed(poseSequence([(.fist, 45)], side: .left, startingAt: 2))
        #expect(h.performer.keyCodes == [KeyCode.rightArrow])
        h.feed(poseSequence([(.open, 8), (.fist, 60)], side: .right, startingAt: 4))
        #expect(h.performer.keyCodes == [KeyCode.rightArrow, KeyCode.leftArrow])
        #expect(h.viewModel.latestGesture == .fistRight)
        #expect(h.viewModel.commandStatus == .submitted)
    }

    @Test func fistRequiresOpenHandToArmAndReopenToRepeat() {
        let h = OfflineHarness()
        h.feed(poseSequence([(.fist, 90)], side: .right, startingAt: 0))
        #expect(h.performer.actions.isEmpty)
        h.feed(poseSequence([(.open, 8), (.fist, 90), (.open, 8), (.fist, 40)],
                            side: .right, startingAt: 3))
        #expect(h.performer.keyCodes == [KeyCode.leftArrow, KeyCode.leftArrow])
    }

    @Test func fistLossInvalidPoseAndGapRequireACompleteReleaseBeforeRearming() {
        let h = OfflineHarness()
        h.feed(poseSequence([(.open, 8), (.fist, 45)], side: .right, startingAt: 0))
        #expect(h.performer.keyCodes == [KeyCode.leftArrow])
        h.feed([AirFrame(timestamp: time(1.77), hands: [])])
        h.feed(poseSequence([(.fist, 90)], side: .right, startingAt: 1.8))
        var incomplete = syntheticJoints(for: .fist)
        incomplete[.ringTip] = nil
        h.feed([jointsFrame(incomplete, at: 4.8)])
        h.feed(poseSequence([(.fist, 45)], side: .right, startingAt: 4.84))
        h.feed(poseSequence([(.fist, 20)], side: .right, startingAt: 8))
        #expect(h.performer.keyCodes == [KeyCode.leftArrow])
        h.feed(poseSequence([(.open, 8), (.fist, 40)], side: .right, startingAt: 9))
        #expect(h.performer.keyCodes == [KeyCode.leftArrow, KeyCode.leftArrow])
    }

    @Test func incompleteFistAtSlideHoldBoundaryCannotFireOrRearm() {
        let h = OfflineHarness()
        h.feed(poseSequence([(.open, 8), (.fist, 10)], side: .right, startingAt: 0))
        #expect(h.performer.actions.isEmpty)
        var incomplete = syntheticJoints(for: .fist)
        incomplete[.ringTip] = nil
        h.feed([jointsFrame(incomplete, at: 0.6)])
        h.feed(poseSequence([(.fist, 60)], side: .right, startingAt: 0.64))
        #expect(h.performer.actions.isEmpty)
        h.feed(poseSequence([(.open, 8), (.fist, 30)], side: .right, startingAt: 3))
        #expect(h.performer.keyCodes == [KeyCode.leftArrow])
    }

    @Test func changingSlideToggleOrProfileWhileFistIsHeldDoesNotDispatch() {
        let h = OfflineHarness()
        h.viewModel.enablePrev = false
        h.viewModel.updateAllowedGestures()
        h.feed(poseSequence([(.open, 8), (.fist, 30)], side: .right, startingAt: 0))
        h.viewModel.enablePrev = true
        h.viewModel.updateAllowedGestures()
        h.feed(poseSequence([(.fist, 30)], side: .right, startingAt: 1.27))
        #expect(h.performer.actions.isEmpty)
        h.viewModel.setProfile(.call)
        h.viewModel.setProfile(.presentation)
        h.feed(poseSequence([(.fist, 30)], side: .right, startingAt: 2.3))
        #expect(h.performer.actions.isEmpty)
        h.feed(poseSequence([(.open, 8), (.fist, 30)], side: .right, startingAt: 3.4))
        #expect(h.performer.keyCodes == [KeyCode.leftArrow])
    }

    @Test func fistCancelsAPartialNextSlidePinch() {
        let h = OfflineHarness()
        h.feed(poseSequence([(.pinch, 6), (.open, 4), (.fist, 20), (.open, 8),
                            (.pinch, 6), (.open, 4)], side: .right, startingAt: 0))
        #expect(h.performer.actions.isEmpty)
    }

    @Test func incompleteFistCannotBeMistakenForNextSlidePinchTaps() {
        let h = OfflineHarness()
        var frames: [AirFrame] = []
        for (pose, count) in [(SyntheticHandPose.fist, 6), (.open, 5), (.fist, 6), (.open, 5)] {
            for _ in 0..<count {
                var joints = syntheticJoints(for: pose)
                if case .fist = pose { joints[.ringTip] = nil }
                frames.append(jointsFrame(joints, at: Double(frames.count) / 30))
            }
        }
        h.feed(frames)
        #expect(h.performer.actions.isEmpty)
    }

    @Test func staleObservationBecomesAnEmptyFrameWithoutLosingItsAge() async throws {
        let tracker = HandTracker(configuresCamera: false)
        let core = AirCore(tracker: tracker)
        let delegate = CountingFrameDelegate()
        core.delegate = delegate
        tracker.publish(["left": syntheticJoints(for: .pinch)], at: Date().addingTimeInterval(-1))
        try await Task.sleep(for: .milliseconds(80))
        #expect(delegate.frames.count == 1)
        #expect(delegate.frames.first?.hands.isEmpty == true)
        #expect(!tracker.session.isRunning)
    }

    @Test func queuedObservationFromPreviousSessionIsRejectedAfterStopAndRestart() async throws {
        let tracker = HandTracker(configuresCamera: false)
        let core = AirCore(tracker: tracker)
        let delegate = CountingFrameDelegate()
        core.delegate = delegate
        tracker.publish(["left": syntheticJoints(for: .pinch)])
        tracker.stop()
        tracker.start()
        let observedAt = Date()
        tracker.publish(["right": syntheticJoints(for: .open)], at: observedAt)
        try await Task.sleep(for: .milliseconds(80))
        #expect(delegate.frames.count == 1)
        #expect(delegate.frames.first?.hand(for: .left) == nil)
        #expect(delegate.frames.first?.hand(for: .right) != nil)
        #expect(delegate.frames.first?.timestamp == observedAt)
        #expect(!tracker.session.isRunning)
    }

    @Test func singlePinchAndLongHoldProduceNoSlide() {
        let h = OfflineHarness()
        h.feed(poseSequence([(.pinch, 6), (.open, 6)], side: .right, startingAt: 0))
        #expect(h.performer.actions.isEmpty)
        h.feed(poseSequence([(.pinch, 40), (.open, 6), (.pinch, 6), (.open, 6)],
                            side: .right, startingAt: 0.4))
        #expect(h.performer.actions.isEmpty)
    }

    @Test func cooldownDoesNotQueueADoublePinchForALaterSingleTap() {
        let h = OfflineHarness()
        h.feed(doublePinchSequence(side: .right, startingAt: 0))
        h.feed(doublePinchSequence(side: .right, startingAt: 0.6))
        h.feed(poseSequence([(.open, 3), (.pinch, 6), (.open, 4)],
                            side: .right, startingAt: 1.2))
        #expect(h.performer.keyCodes == [KeyCode.rightArrow])
    }

    @Test func changingProfileCancelsAPartialDoublePinch() {
        let h = OfflineHarness()
        h.feed(poseSequence([(.pinch, 6), (.open, 4)], side: .right, startingAt: 0))
        h.viewModel.setProfile(.call)
        h.viewModel.setProfile(.presentation)
        h.feed(poseSequence([(.pinch, 6), (.open, 4)], side: .right, startingAt: 0.34))
        #expect(h.performer.actions.isEmpty)
    }

    @Test func losingHandOrFrameContinuityCancelsAPartialDoublePinch() {
        for gap in [false, true] {
            let h = OfflineHarness()
            h.feed(poseSequence([(.pinch, 6), (.open, 4)], side: .right, startingAt: 0))
            if !gap { h.feed([AirFrame(timestamp: time(0.32), hands: [])]) }
            h.feed(poseSequence([(.pinch, 6), (.open, 4)],
                                side: .right, startingAt: gap ? 0.8 : 0.34))
            #expect(h.performer.actions.isEmpty)
        }
    }

    @Test func disablingSlideGestureCancelsAPartialDoublePinch() {
        let h = OfflineHarness()
        h.feed(poseSequence([(.pinch, 6), (.open, 4)], side: .right, startingAt: 0))
        h.viewModel.enableNext = false
        h.viewModel.updateAllowedGestures()
        h.viewModel.enableNext = true
        h.viewModel.updateAllowedGestures()
        h.feed(poseSequence([(.pinch, 6), (.open, 4)], side: .right, startingAt: 0.34))
        #expect(h.performer.actions.isEmpty)
    }

    @Test func stoppingRejectsQueuedFramesAndClearsPartialGestures() {
        let h = OfflineHarness()
        h.feed(poseSequence([(.pinch, 6), (.open, 4)], side: .right, startingAt: 0))
        h.viewModel.stop()
        h.feed(doublePinchSequence(side: .right, startingAt: 0.34))
        #expect(h.performer.actions.isEmpty)
        h.viewModel.start()
        h.feed(poseSequence([(.pinch, 6), (.open, 4)], side: .right, startingAt: 1))
        #expect(h.performer.actions.isEmpty)
    }

    @Test func missingAccessibilityBlocksCommandsAndMouse() {
        let h = OfflineHarness(accessibility: .notTrusted)
        h.feed(doublePinchSequence(side: .right, startingAt: 0))
        #expect(h.performer.actions.isEmpty)
        #expect(h.viewModel.latestGesture == .pinchDoubleRight)
        #expect(h.viewModel.commandStatus == .blockedAccessibility)
        h.viewModel.setProfile(.deepwork)
        var joints = pinkyJoints()
        joints[.indexTip] = CGPoint(x: 0.5, y: 0.7)
        joints[.littleTip] = CGPoint(x: 0.55, y: 0.45)
        for i in 0..<6 { h.feed([jointsFrame(joints, at: 1 + Double(i) / 30)]) }
        #expect(h.viewModel.pointerLocation == nil)
        #expect(h.performer.actions.isEmpty)
    }

    @Test func revocationIsCheckedAtSubmissionAndGrantCancelsPendingGesture() {
        let h = OfflineHarness()
        h.permissions.setAccessibility(.notTrusted)
        h.feed(doublePinchSequence(side: .right, startingAt: 0))
        #expect(h.performer.actions.isEmpty)
        #expect(h.viewModel.commandStatus == .blockedAccessibility)
        h.permissions.setAccessibility(.trusted)
        h.feed(doublePinchSequence(side: .right, startingAt: 1))
        #expect(h.performer.actions.isEmpty)
        #expect(h.viewModel.commandStatus == .permissionChanged)
        h.feed(doublePinchSequence(side: .right, startingAt: 2))
        #expect(h.performer.keyCodes == [KeyCode.rightArrow])
    }

    @Test func performerFailureIsReportedWithoutClaimingDelivery() {
        let h = OfflineHarness()
        h.performer.succeeds = false
        h.feed(doublePinchSequence(side: .right, startingAt: 0))
        #expect(h.performer.actions.count == 1)
        #expect(h.viewModel.commandStatus == .failed)
    }

    @Test func callMuteIsOneShortcutPerPinkyHold() {
        let h = OfflineHarness()
        h.viewModel.setProfile(.call)
        for i in 0...60 { h.feed([jointsFrame(pinkyJoints(), at: Double(i) / 30)]) }
        #expect(h.performer.keyCodes == [KeyCode.a])
        if case .shortcut(let shortcut)? = h.performer.actions.first {
            #expect(shortcut.modifiers == [.command, .shift])
        } else { Issue.record("Mute must map to a shortcut") }
    }

    @Test func deepworkFistFiresOnceAndLossCancelsAnIncompleteHold() {
        let h = OfflineHarness()
        h.viewModel.setProfile(.deepwork)
        h.feed(poseSequence([(.fist, 60)], side: .right, startingAt: 0))
        #expect(h.performer.keyCodes == [49])
        h.feed([AirFrame(timestamp: time(2), hands: [])])
        h.feed(poseSequence([(.fist, 20)], side: .right, startingAt: 2.1))
        h.feed([AirFrame(timestamp: time(2.8), hands: [])])
        h.feed(poseSequence([(.fist, 20)], side: .right, startingAt: 2.9))
        #expect(h.performer.keyCodes == [49])
    }

    @Test func missingJointAtFistHoldBoundaryCancelsPlayPause() {
        let h = OfflineHarness()
        h.viewModel.setProfile(.deepwork)
        h.feed(poseSequence([(.fist, 32)], side: .right, startingAt: 0))
        #expect(h.performer.actions.isEmpty)

        var incomplete = syntheticJoints(for: .fist)
        incomplete[.ringTip] = nil
        h.feed([jointsFrame(incomplete, at: 1.07)])
        #expect(h.performer.actions.isEmpty)

        // Complete observations must start a new hold after a partial pose.
        h.feed(poseSequence([(.fist, 20)], side: .right, startingAt: 1.11))
        #expect(h.performer.actions.isEmpty)
    }

    @Test func horizontalAndVerticalDragRespectIndependentToggles() {
        for horizontal in [true, false] {
            let h = OfflineHarness()
            h.viewModel.setProfile(.deepwork)
            h.viewModel.enableScroll = !horizontal
            h.viewModel.enableScrub = horizontal
            h.feed(dragSequence(horizontal: horizontal, startingAt: 0))
            #expect(!h.performer.actions.isEmpty)
            for action in h.performer.actions {
                guard case .scroll(let dx, let dy) = action else {
                    Issue.record("Drag must map to scroll events")
                    continue
                }
                #expect(horizontal ? dx != 0 && dy == 0 : dx == 0 && dy != 0)
            }
            let count = h.performer.actions.count
            h.viewModel.enableScroll = horizontal
            h.viewModel.enableScrub = !horizontal
            h.viewModel.resetContinuousGestures()
            h.feed(dragSequence(horizontal: horizontal, startingAt: 2))
            #expect(h.performer.actions.count == count)
        }
    }

    @Test func changingProfileCancelsCruiseAndReanchorsDrag() {
        let h = OfflineHarness()
        h.viewModel.setProfile(.deepwork)
        h.feed(dragSequence(horizontal: true, startingAt: 0))
        let count = h.performer.actions.count
        #expect(count > 0)
        h.viewModel.setProfile(.presentation)
        h.viewModel.setProfile(.deepwork)
        h.feed(poseSequence([(.pinch, 10)], side: .left, startingAt: 2))
        #expect(h.performer.actions.count == count)
    }

    @Test func stationaryOffsetScrollsUntilReleaseAndNewPinchStartsNeutral() {
        let h = OfflineHarness()
        h.viewModel.setProfile(.deepwork)
        h.feed(dragSequence(horizontal: false, startingAt: 0))
        let firstCount = h.performer.actions.count
        h.feed((0..<20).map { dragFrame(offset: 0.4, horizontal: false, at: 1 + Double($0) / 30) })
        #expect(h.performer.actions.count > firstCount + 15)
        let heldCount = h.performer.actions.count
        h.feed([dragFrame(offset: 0.4, horizontal: false, at: 1.67, pose: .open)])
        #expect(h.performer.actions.count == heldCount)
        h.feed((0..<20).map { dragFrame(offset: 0.4, horizontal: false, at: 1.7 + Double($0) / 30) })
        #expect(h.performer.actions.count == heldCount)
    }

    @Test func rawPinchReleaseCancelsScrollBeforeSmoothedStateCatchesUp() {
        let h = OfflineHarness()
        h.viewModel.setProfile(.deepwork)
        h.feed(dragSequence(horizontal: false, startingAt: 0))
        let count = h.performer.actions.count
        #expect(count > 0)
        var joints = syntheticJoints(for: .pinch)
        joints[.indexTip] = CGPoint(x: 0.2 + sqrt(0.12), y: 0)
        joints = joints.mapValues { CGPoint(x: $0.x * 0.1 + 0.4, y: $0.y * 0.1 + 0.7) }
        h.feed([jointsFrame(joints, at: 1, side: .left)])
        #expect(h.viewModel.leftHandState.pinch)
        #expect(h.performer.actions.count == count)
    }

    @Test func permissionChangeCancelsEveryAxisInThePendingScrollBatch() {
        let h = OfflineHarness(accessibility: .notTrusted)
        h.viewModel.setProfile(.deepwork)
        h.feed((0..<3).map { dragFrame(offset: 0, horizontal: true, at: Double($0) / 30) })
        h.permissions.setAccessibility(.trusted)
        let joints = syntheticJoints(for: .pinch).mapValues {
            CGPoint(x: $0.x * 0.1 + 0.7, y: $0.y * 0.1 + 0.6)
        }
        h.feed([jointsFrame(joints, at: 0.1, side: .left)])
        #expect(h.performer.actions.isEmpty)
        #expect(h.viewModel.commandStatus == .permissionChanged)
        h.feed((0..<4).map { jointsFrame(joints, at: 0.14 + Double($0) / 30, side: .left) })
        #expect(h.performer.actions.isEmpty)
    }

    @Test func stoppingOrRevokingCameraCancelsScrollWithoutResumingOldOffset() {
        for revoke in [false, true] {
            let h = OfflineHarness()
            h.viewModel.setProfile(.deepwork)
            h.feed(dragSequence(horizontal: false, startingAt: 0))
            let count = h.performer.actions.count
            #expect(count > 0)
            if revoke {
                h.permissions.setCamera(.denied)
                h.viewModel.refreshPermissionSnapshot()
            } else { h.viewModel.stop() }
            h.feed((0..<10).map { dragFrame(offset: 0.4, horizontal: false, at: 1 + Double($0) / 30) })
            #expect(h.performer.actions.count == count)
            h.permissions.setCamera(.authorized)
            h.viewModel.refreshPermissionSnapshot()
            h.viewModel.start()
            h.feed((0..<20).map { dragFrame(offset: 0.4, horizontal: false, at: 1.4 + Double($0) / 30) })
            #expect(h.performer.actions.count == count)
        }
    }

    @Test func incompleteFistAndDegenerateScaleRemainUnknown() {
        var joints = syntheticJoints(for: .fist)
        joints[.ringTip] = nil
        #expect(HandPoseMetrics.fistMetric(from: joints) == nil)
        joints = [.wrist: .zero, .middleMCP: .zero, .thumbTip: .zero, .indexTip: .zero]
        #expect(HandPoseMetrics.pinchDistanceNormalized(from: joints) == nil)
        joints[.middleMCP] = CGPoint(x: CGFloat.nan, y: 0)
        #expect(HandPoseMetrics.pinchDistanceNormalized(from: joints) == nil)
    }
}

@MainActor
struct OfflineHarness {
    let core: AirCore
    let viewModel: ContentViewModel
    let performer = OfflineRecordingPerformer()
    let permissions: MutableOfflinePermissions

    init(accessibility: AccessibilityPermissionStatus = .trusted) {
        permissions = MutableOfflinePermissions(accessibility: accessibility)
        core = AirCore(tracker: HandTracker(configuresCamera: false))
        viewModel = ContentViewModel(engine: core, gestureRecognizer: AirGestureRecognizer(),
                                     systemActions: performer, permissionClient: permissions)
        viewModel.start()
    }

    func feed(_ frames: [AirFrame]) {
        for frame in frames { viewModel.airCore(core, didUpdate: frame) }
    }
}

@MainActor
final class OfflineRecordingPerformer: SystemActionPerforming {
    var actions: [SystemAction] = []
    var succeeds = true
    var onPerform: ((SystemAction) -> Void)?
    var clicks: [Bool] { actions.compactMap { if case .clickMouse(let right) = $0 { right } else { nil } } }
    var moves: [CGVector] { actions.compactMap { if case .moveMouseBy(let delta) = $0 { delta } else { nil } } }
    var scrolls: [SystemAction] { actions.filter { if case .scroll = $0 { true } else { false } } }
    var keyCodes: [CGKeyCode] {
        actions.compactMap { if case .shortcut(let s) = $0 { s.keyCode } else { nil } }
    }
    func perform(_ action: SystemAction) -> Bool {
        actions.append(action)
        onPerform?(action)
        return succeeds
    }
}

nonisolated final class MutableOfflinePermissions: PermissionClient, @unchecked Sendable {
    private let lock = NSLock()
    private var accessibility: AccessibilityPermissionStatus
    private var camera: CameraPermissionStatus = .authorized
    init(accessibility: AccessibilityPermissionStatus) { self.accessibility = accessibility }
    func setAccessibility(_ status: AccessibilityPermissionStatus) {
        lock.lock(); defer { lock.unlock() }
        accessibility = status
    }
    func setCamera(_ status: CameraPermissionStatus) {
        lock.lock(); defer { lock.unlock() }
        camera = status
    }
    func cameraStatus() -> CameraPermissionStatus {
        lock.lock(); defer { lock.unlock() }
        return camera
    }
    func accessibilityStatus() -> AccessibilityPermissionStatus {
        lock.lock(); defer { lock.unlock() }
        return accessibility
    }
    func requestCameraAccess() async -> CameraPermissionStatus {
        preconditionFailure("Offline tests must never request camera access")
    }
    func promptForAccessibilityIfNeeded() -> AccessibilityPermissionStatus {
        preconditionFailure("Offline tests must never prompt for permissions")
    }
}

@MainActor
private final class CountingFrameDelegate: AirCoreDelegate {
    var frames: [AirFrame] = []
    func airCore(_ core: AirCore, didUpdate frame: AirFrame) { frames.append(frame) }
}

func poseSequence(_ phases: [(SyntheticHandPose, Int)], side: AirHandSide, startingAt start: Double) -> [AirFrame] {
    var frames: [AirFrame] = []
    for (pose, count) in phases {
        for _ in 0..<count {
            frames.append(frame(at: time(start + Double(frames.count) / 30), side: side, pose: pose))
        }
    }
    return frames
}

func doublePinchSequence(side: AirHandSide, startingAt start: Double) -> [AirFrame] {
    poseSequence([(.pinch, 6), (.open, 4), (.pinch, 6), (.open, 2)], side: side, startingAt: start)
}

private func dragSequence(horizontal: Bool, startingAt start: Double) -> [AirFrame] {
    (0..<30).map { i in
        let displacement = min(CGFloat(i) * 0.02, 0.4)
        return dragFrame(offset: displacement, horizontal: horizontal, at: start + Double(i) / 30)
    }
}

private func dragFrame(offset: CGFloat, horizontal: Bool, at timestamp: Double,
                       pose: SyntheticHandPose = .pinch) -> AirFrame {
    let joints = syntheticJoints(for: pose).mapValues { point in
        CGPoint(x: point.x * 0.1 + 0.4 + (horizontal ? offset : 0),
                y: point.y * 0.1 + 0.3 + (horizontal ? 0 : offset))
    }
    return jointsFrame(joints, at: timestamp, side: .left)
}
