import Foundation
import Testing
@testable import AirPointer

@MainActor
@Suite("Cursor readiness feedback", .serialized)
struct CursorFeedbackBehaviorTests {
    @Test func heldButtonKeepsADistinctStaticHaloAfterOnePulse() {
        var state = CursorFeedbackState()
        state.recognize(at: 0)
        state.update(ready: true, at: 0.1, pressedButton: .left)
        #expect(state.phase == .recognized && state.pressedButton == .left)
        for i in 2...60 { state.update(ready: false, at: Double(i) / 10, pressedButton: .left) }
        #expect(state.phase == .pressed && state.pressedButton == .left)
        #expect(state.commandID == 1)
        state.update(ready: true, at: 6.1)
        #expect(state.phase == .ready && state.pressedButton == nil)
    }

    @Test func cancellingHoldClearsItsVisualState() {
        var state = CursorFeedbackState()
        state.update(ready: true, at: 0, pressedButton: .middle)
        state.cancel()
        #expect(state.phase == .hidden && state.pressedButton == nil)
        state.update(ready: true, at: 1, pressedButton: .right)
        state.expire(at: 1.3)
        #expect(state.phase == .hidden && state.pressedButton == nil)
    }

    @Test func readyStaysStaticAndConfirmationReturnsToReady() {
        var state = CursorFeedbackState()
        #expect(state.phase == .hidden)
        state.update(ready: true, at: 0)
        for i in 1...100 { state.update(ready: true, at: Double(i) / 30) }
        #expect(state.phase == .ready)
        #expect(state.commandID == 0)
        state.recognize(at: 4)
        #expect(state.phase == .recognized && state.commandID == 1)
        state.update(ready: true, at: 4.1)
        state.expire(at: 4.23)
        #expect(state.phase == .ready && state.commandID == 1)
    }

    @Test func standaloneCommandEndsWithoutLeavingAReadyRing() {
        var state = CursorFeedbackState()
        state.recognize(at: 1)
        state.update(ready: false, at: 1.1)
        #expect(state.phase == .recognized)
        state.expire(at: 1.23)
        #expect(state.phase == .hidden)
    }

    @Test func cancellationInterruptsPulseAndReentryDoesNotReplayIt() {
        var state = CursorFeedbackState()
        state.update(ready: true, at: 0)
        state.recognize(at: 0.01)
        state.cancel()
        #expect(state.phase == .hidden)
        state.update(ready: true, at: 0.02)
        #expect(state.phase == .ready && state.commandID == 1)
        state.expire(at: 0.03)
        #expect(state.phase == .ready && state.commandID == 1)
    }

    @Test func stalledFramesAndInvalidClockCannotLeaveHaloVisible() {
        for invalid in [0.251, -1, Double.nan, .infinity] {
            var state = CursorFeedbackState()
            state.update(ready: true, at: 0)
            state.expire(at: invalid)
            #expect(state.phase == .hidden)
        }
        var state = CursorFeedbackState()
        state.update(ready: true, at: 0)
        state.expire(at: AppConfig.GestureTuning.maximumFrameGap)
        #expect(state.phase == .ready)
        state.recognize(at: .nan)
        #expect(state.phase == .hidden)
    }

    @Test func haloFrameKeepsTheCursorCenteredInGlobalAppKitPoints() {
        for cursor in [CGPoint(x: -1200, y: -300), CGPoint(x: 0, y: 0), CGPoint(x: 2500, y: 1400)] {
            let frame = CursorHaloGeometry.frame(at: cursor)
            #expect(CGPoint(x: frame.midX, y: frame.midY) == cursor)
            #expect(frame.size == CGSize(width: 64, height: 64))
        }
    }

    @Test func rightHandDiscreteCommandPulsesOnceAndExpires() {
        let h = OfflineHarness()
        h.feed(doublePinchSequence(side: .right, startingAt: 0))
        #expect(h.viewModel.cursorFeedback.phase == .recognized)
        #expect(h.viewModel.cursorFeedback.commandID == 1)
        h.viewModel.expireCursorFeedback(at: h.feedbackClock.now + 0.23)
        #expect(h.viewModel.cursorFeedback.phase == .hidden)
        #expect(h.performer.keyCodes == [KeyCode.rightArrow])
    }

    @Test func rightHandConfirmationRemainsVisibleWhileLeftHandIsAlreadyRepositioning() {
        let h = OfflineHarness()
        h.feed(doublePinchSequence(side: .right, startingAt: 0).map {
            AirFrame(timestamp: $0.timestamp, hands: $0.hands + [buttonHand(nil)])
        })
        #expect(h.viewModel.cursorFeedback.phase == .recognized)
        #expect(h.viewModel.cursorFeedback.commandID == 1)
        #expect(h.performer.keyCodes == [KeyCode.rightArrow])
    }

    @Test func blockedFailedAndDiagnosticCommandsNeverPulse() {
        for mode in 0..<3 {
            let h = OfflineHarness(accessibility: mode == 0 ? .notTrusted : .trusted)
            if mode == 1 { h.performer.succeeds = false }
            if mode == 2 { h.viewModel.diagnosticOnly = true }
            h.feed(doublePinchSequence(side: .right, startingAt: 0))
            #expect(h.viewModel.cursorFeedback.phase == .hidden)
            #expect(h.viewModel.cursorFeedback.commandID == 0)
        }
    }

    @Test func haloPreferencePersistsWithoutChangingRecognitionSettings() throws {
        let suite = "AirPointerCursorFeedbackTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        func model() -> ContentViewModel {
            ContentViewModel(engine: AirCore(tracker: HandTracker(configuresCamera: false)),
                             gestureRecognizer: AirGestureRecognizer(),
                             systemActions: OfflineRecordingPerformer(),
                             permissionClient: MutableOfflinePermissions(accessibility: .trusted),
                             feedbackDefaults: defaults)
        }
        let first = model()
        #expect(first.cursorFeedbackEnabled)
        first.cursorFeedbackEnabled = false
        #expect(!model().cursorFeedbackEnabled)
        #expect(first.enableNext && first.enablePrev)
        first.cursorFeedbackEnabled = true
        #expect(model().cursorFeedbackEnabled)
    }
}
