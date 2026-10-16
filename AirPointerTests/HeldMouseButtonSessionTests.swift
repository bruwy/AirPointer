import CoreGraphics
import Foundation
import Testing
@testable import AirPointer

@MainActor
@Suite("Balanced held mouse event delivery", .serialized)
struct HeldMouseButtonSessionTests {
    @Test func heldGestureSendsOneDownAndOneUpForEachButton() {
        for button in MouseButton.allCases {
            let session = HeldMouseButtonSession()
            let recorder = ButtonEventRecorder()
            for _ in 0..<60 { #expect(session.update(desired: button, perform: recorder.perform)) }
            for _ in 0..<10 { #expect(session.update(desired: nil, perform: recorder.perform)) }
            #expect(recorder.events == [.init(button: button, pressed: true), .init(button: button, pressed: false)])
            #expect(session.pressedButton == nil)
        }
    }

    @Test func switchesReleaseBeforeTheReplacementDown() {
        let session = HeldMouseButtonSession()
        let recorder = ButtonEventRecorder()
        session.update(desired: .left, perform: recorder.perform)
        session.update(desired: .middle, perform: recorder.perform)
        session.update(desired: .right, perform: recorder.perform)
        session.release(perform: recorder.perform)
        #expect(recorder.events == [.init(button: .left, pressed: true), .init(button: .left, pressed: false),
                                    .init(button: .middle, pressed: true), .init(button: .middle, pressed: false),
                                    .init(button: .right, pressed: true), .init(button: .right, pressed: false)])
    }

    @Test func failedReleaseRetainsOwnershipAndBlocksReplacementUntilRetry() {
        let session = HeldMouseButtonSession()
        let recorder = ButtonEventRecorder()
        session.update(desired: .middle, perform: recorder.perform)
        recorder.succeed = false
        #expect(!session.update(desired: .right, perform: recorder.perform))
        #expect(session.pressedButton == .middle && session.releasePending)
        #expect(!recorder.events.contains(.init(button: .right, pressed: true)))
        recorder.succeed = true
        #expect(session.update(desired: nil, perform: recorder.perform))
        #expect(session.pressedButton == nil && !session.releasePending)
    }

    @Test func reentrantStopDuringDownBalancesItAndDoesNotResurrectTheHold() {
        let session = HeldMouseButtonSession()
        let recorder = ButtonEventRecorder()
        let accepted = session.update(desired: .left) { action in
            let success = recorder.perform(action)
            if case .mouseButton(_, pressed: true) = action { session.release(perform: recorder.perform) }
            return success
        }
        #expect(!accepted)
        #expect(session.pressedButton == nil)
        #expect(recorder.events == [.init(button: .left, pressed: true), .init(button: .left, pressed: false)])
    }

    @Test func failedDownStillAttemptsCleanupAndRepeatedCleanupIsIdempotent() {
        let session = HeldMouseButtonSession()
        let recorder = ButtonEventRecorder()
        recorder.succeed = false
        #expect(!session.update(desired: .right, perform: recorder.perform))
        #expect(session.releasePending)
        recorder.succeed = true
        session.release(perform: recorder.perform)
        let count = recorder.events.count
        session.release(perform: recorder.perform)
        #expect(session.pressedButton == nil)
        #expect(recorder.events.count == count)
    }

    @Test func quartzEventsUseCorrectButtonNumbersAndDragTypes() throws {
        let point = CGPoint(x: -150, y: 300)
        let downs: [CGEventType] = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        let ups: [CGEventType] = [.leftMouseUp, .rightMouseUp, .otherMouseUp]
        let drags: [CGEventType] = [.leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        for button in MouseButton.allCases {
            let down = try #require(MouseController.buttonEvent(button, pressed: true, at: point))
            let up = try #require(MouseController.buttonEvent(button, pressed: false, at: point))
            let drag = try #require(MouseController.movementEvent(at: point, dragging: button))
            #expect(down.type == downs[button.rawValue] && up.type == ups[button.rawValue])
            #expect(drag.type == drags[button.rawValue])
            #expect(down.location == point && up.location == point && drag.location == point)
            #expect(drag.getIntegerValueField(.mouseEventButtonNumber) == Int64(button.rawValue))
        }
        #expect(MouseController.movementEvent(at: point, dragging: nil)?.type == .mouseMoved)
        #expect(MouseController.buttonEvent(.left, pressed: true, at: CGPoint(x: CGFloat.nan, y: 0)) == nil)
    }
}

@MainActor
private final class ButtonEventRecorder {
    struct Event: Equatable {
        let button: MouseButton
        let pressed: Bool
    }
    var events: [Event] = []
    var succeed = true
    func perform(_ action: SystemAction) -> Bool {
        guard case .mouseButton(let button, let pressed) = action else { return false }
        events.append(Event(button: button, pressed: pressed))
        return succeed
    }
}
