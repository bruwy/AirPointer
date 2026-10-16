import AppKit
import Foundation
import Testing
import Vision
@testable import AirPointer

@MainActor
@Suite("Global gesture pause and neutral resume", .serialized)
struct GlobalGestureControlTests {
    @Test func pauseReleasesEveryButtonImmediatelyAndHidesBothOverlays() {
        for button in MouseButton.allCases {
            let h = GlobalControlHarness(.deepwork)
            h.feed(left: buttonHand(nil, closed: true), count: 8)
            h.feed(left: buttonHand(button), right: rightLaserHand(), count: 12)
            #expect(h.base.performer.buttonDowns == [button])
            #expect(h.base.viewModel.pointerLocation != nil)
            h.base.viewModel.gesturesEnabled = false
            #expect(h.base.performer.buttonUps == [button])
            #expect(h.base.viewModel.pointerLocation == nil)
            #expect(h.base.viewModel.cursorFeedback.phase == .hidden)
            let count = h.base.performer.actions.count
            h.feed(left: buttonHand(button), right: rightLaserHand(), count: 60)
            h.scroll()
            #expect(h.base.performer.actions.count == count)
            #expect(h.base.viewModel.latestGesture == nil)
            #expect(!h.base.viewModel.handJoints.isEmpty)
        }
    }

    @Test func resumingWithAHeldButtonCannotRepressUntilNeutral() {
        for button in MouseButton.allCases {
            let h = GlobalControlHarness()
            h.feed(left: buttonHand(nil, closed: true), count: 8)
            h.feed(left: buttonHand(button), count: 12)
            h.base.viewModel.gesturesEnabled = false
            h.base.viewModel.gesturesEnabled = true
            h.feed(left: buttonHand(button), count: 60)
            #expect(h.base.performer.buttonDowns == [button])
            #expect(h.base.performer.buttonUps == [button])
            #expect(h.base.viewModel.gestureResumeHint?.contains("Left") == true)
            h.feed(left: buttonHand(nil, closed: true), count: 12)
            h.feed(left: buttonHand(button), count: 12)
            #expect(h.base.performer.buttonDowns == [button, button])
            #expect(h.base.viewModel.gestureResumeHint?.contains("Left") == false)
        }
    }

    @Test func scrollStopsWhilePausedAndCannotResumeFromAnExistingPinch() {
        let h = GlobalControlHarness(.deepwork)
        h.scroll()
        #expect(!h.base.performer.scrolls.isEmpty)
        h.base.viewModel.gesturesEnabled = false
        let count = h.base.performer.actions.count
        h.scroll()
        h.base.viewModel.gesturesEnabled = true
        h.scroll()
        #expect(h.base.performer.actions.count == count)
        h.feed(left: buttonHand(nil, closed: true), count: 12)
        h.scroll()
        #expect(h.base.performer.actions.count > count)
        #expect(h.base.performer.buttonDowns.isEmpty)
    }

    @Test func rightFistAndMuteCannotFireOnResumeUntilThatHandOpens() {
        for profile in AirProfileKind.allCases {
            let h = GlobalControlHarness(profile)
            let command = profile == .call ? pinkyJoints() : syntheticJoints(for: .fist)
            h.base.viewModel.gesturesEnabled = false
            h.feed(rightJoints: command, count: 45)
            h.base.viewModel.gesturesEnabled = true
            h.feed(rightJoints: command, count: 60)
            #expect(h.base.performer.actions.isEmpty)
            h.feed(rightJoints: buttonHand(nil).joints, count: 20)
            h.feed(rightJoints: command, count: 60)
            let expected: CGKeyCode = profile == .presentation ? KeyCode.leftArrow : (profile == .call ? KeyCode.a : 49)
            #expect(h.base.performer.keyCodes == [expected])
            #expect(h.base.performer.buttonDowns.isEmpty)
        }
    }

    @Test func partialDoublePinchCannotSurviveTheGlobalPause() {
        let h = GlobalControlHarness()
        h.feed(rightJoints: buttonHand(nil).joints, count: 10)
        h.feed(rightJoints: syntheticJoints(for: .pinch), count: 6)
        h.feed(rightJoints: syntheticJoints(for: .open), count: 4)
        h.base.viewModel.gesturesEnabled = false
        h.base.viewModel.gesturesEnabled = true
        h.feed(rightJoints: buttonHand(nil).joints, count: 20)
        h.feed(rightJoints: syntheticJoints(for: .pinch), count: 6)
        h.feed(rightJoints: syntheticJoints(for: .open), count: 4)
        #expect(h.base.performer.keyCodes.isEmpty)
    }

    @Test func laserAlsoWaitsForNeutralAfterResume() {
        let h = GlobalControlHarness(.deepwork)
        h.base.viewModel.gesturesEnabled = false
        h.base.viewModel.gesturesEnabled = true
        h.feed(right: rightLaserHand(), count: 20)
        #expect(h.base.viewModel.pointerLocation == nil)
        h.feed(rightJoints: buttonHand(nil).joints, count: 12)
        h.feed(right: rightLaserHand(), count: 12)
        #expect(h.base.viewModel.pointerLocation != nil)
        #expect(h.base.performer.actions.isEmpty)
    }

    @Test func pausingDuringDownReleasesBeforeAnyDragCanBeSent() {
        let h = GlobalControlHarness()
        defer { h.base.performer.onPerform = nil }
        h.feed(left: buttonHand(nil, closed: true), count: 8)
        h.base.performer.onPerform = { action in
            if case .mouseButton(_, pressed: true) = action { h.base.viewModel.gesturesEnabled = false }
        }
        h.feed(left: buttonHand(.left), count: 20)
        #expect(h.base.performer.buttonDowns == [.left])
        #expect(h.base.performer.buttonUps == [.left])
        #expect(h.base.performer.drags.isEmpty)
        #expect(h.base.viewModel.cursorFeedback.phase == .hidden)
        #expect(h.base.viewModel.commandStatus == .idle)
    }

    @Test func failedReleaseRemainsOwnedAndIsRetriedEvenWhileGesturesAreOff() {
        let h = GlobalControlHarness()
        h.feed(left: buttonHand(nil, closed: true), count: 8)
        h.feed(left: buttonHand(.right), count: 12)
        h.base.performer.succeeds = false
        h.base.viewModel.gesturesEnabled = false
        #expect(h.base.viewModel.commandStatus == .failed)
        h.base.performer.succeeds = true
        h.base.viewModel.expireTrackingState()
        #expect(h.base.performer.buttonUps == [.right, .right])
        h.base.viewModel.expireTrackingState()
        #expect(h.base.performer.buttonUps == [.right, .right])
    }

    @Test func pausePreferenceSurvivesRelaunch() {
        let suite = "AirPointer.GlobalControlTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = model(defaults)
        first.gesturesEnabled = false
        let second = model(defaults)
        #expect(!second.gesturesEnabled)
        second.gesturesEnabled = true
        #expect(defaults.bool(forKey: ContentViewModel.gesturesEnabledPreferenceKey))
    }

    @Test func missingOrInterruptedNeutralCannotRearmAHand() {
        let h = GlobalControlHarness()
        h.base.viewModel.gesturesEnabled = false
        h.base.viewModel.gesturesEnabled = true
        h.feed(left: buttonHand(nil, closed: true), count: 2)
        h.feed(count: 2)
        h.feed(left: buttonHand(.left), count: 30)
        #expect(h.base.performer.buttonDowns.isEmpty)
        h.feed(left: buttonHand(nil, closed: true), count: 2)
        h.now += 0.6
        h.feed(left: buttonHand(nil, closed: true), count: 1)
        h.feed(left: buttonHand(.left), count: 30)
        #expect(h.base.performer.buttonDowns.isEmpty)
    }

    private func model(_ defaults: UserDefaults) -> ContentViewModel {
        ContentViewModel(engine: AirCore(tracker: HandTracker(configuresCamera: false)),
                         gestureRecognizer: AirGestureRecognizer(), systemActions: OfflineRecordingPerformer(),
                         permissionClient: MutableOfflinePermissions(accessibility: .trusted), feedbackDefaults: defaults)
    }
}

@MainActor
private final class GlobalControlHarness {
    let base = OfflineHarness()
    var now: TimeInterval = 0
    init(_ profile: AirProfileKind = .presentation) { base.viewModel.setProfile(profile) }
    func feed(left: AirHandSnapshot? = nil, right: AirHandSnapshot? = nil, count: Int) {
        for _ in 0..<count {
            var hands: [AirHandSnapshot] = []
            if let left { hands.append(left) }
            if let right { hands.append(AirHandSnapshot(side: .right, joints: right.joints, wrist: right.wrist)) }
            base.feed([AirFrame(timestamp: Date(timeIntervalSinceReferenceDate: 10000 + now), hands: hands)])
            now += 1.0 / 30
        }
    }
    func feed(rightJoints: [VNHumanHandPoseObservation.JointName: CGPoint], count: Int) {
        feed(right: AirHandSnapshot(side: .right, joints: rightJoints, wrist: rightJoints[.wrist]), count: count)
    }
    func scroll() {
        for i in 0..<30 {
            feed(left: indexScrollHand(wrist: CGPoint(x: 0.4 + CGFloat(i) * 0.003, y: 0.3)), count: 1)
        }
    }
}
