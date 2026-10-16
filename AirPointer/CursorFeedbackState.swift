import CoreGraphics
import Foundation

/// Visual feedback only; this state never arms, cancels or dispatches a gesture.
struct CursorFeedbackState: Equatable {
    enum Phase: Equatable { case hidden, ready, recognized, pressed }

    static let confirmationDuration: TimeInterval = 0.22
    private(set) var phase: Phase = .hidden
    private(set) var commandID: UInt = 0
    private(set) var pressedButton: MouseButton?
    private var ready = false
    private var lastFrameAt: TimeInterval?
    private var confirmedUntil: TimeInterval?

    mutating func update(ready: Bool, at now: TimeInterval, pressedButton: MouseButton? = nil) {
        guard now.isFinite else { cancel(); return }
        self.ready = ready
        self.pressedButton = pressedButton
        lastFrameAt = now
        refresh(at: now)
    }

    mutating func recognize(at now: TimeInterval) {
        guard now.isFinite else { cancel(); return }
        commandID &+= 1
        lastFrameAt = now
        confirmedUntil = now + Self.confirmationDuration
        phase = .recognized
    }

    mutating func expire(at now: TimeInterval) {
        guard now.isFinite, let lastFrameAt, now >= lastFrameAt,
              now - lastFrameAt <= AppConfig.GestureTuning.maximumFrameGap else {
            cancel(); return
        }
        refresh(at: now)
    }

    mutating func cancel() {
        ready = false
        pressedButton = nil
        lastFrameAt = nil
        confirmedUntil = nil
        phase = .hidden
    }

    private mutating func refresh(at now: TimeInterval) {
        if let confirmedUntil, now < confirmedUntil {
            phase = .recognized
        } else {
            confirmedUntil = nil
            phase = pressedButton != nil ? .pressed : (ready ? .ready : .hidden)
        }
    }
}

enum CursorHaloGeometry {
    static let size: CGFloat = 64

    /// NSEvent and NSWindow share global AppKit points, including negative displays.
    static func frame(at cursor: CGPoint) -> CGRect {
        CGRect(x: cursor.x - size / 2, y: cursor.y - size / 2, width: size, height: size)
    }
}
