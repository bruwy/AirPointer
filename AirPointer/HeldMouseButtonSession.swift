import Foundation

/// Owns only buttons pressed by this session. Failed ups block all new downs.
@MainActor
final class HeldMouseButtonSession {
    private(set) var pressedButton: MouseButton?
    private(set) var releasePending = false
    private var releasing = false
    private var revision = 0

    @discardableResult
    func update(desired: MouseButton?, perform: (SystemAction) -> Bool) -> Bool {
        if releasePending || pressedButton != desired {
            guard release(perform: perform) else { return false }
        }
        guard let desired, pressedButton == nil else { return true }
        revision &+= 1
        let current = revision
        // Record ownership before dispatch so a reentrant stop can release it.
        pressedButton = desired
        let success = perform(.mouseButton(desired, pressed: true))
        guard current == revision else { return false }
        if !success {
            _ = release(perform: perform)
            return false
        }
        return true
    }

    @discardableResult
    func release(perform: (SystemAction) -> Bool) -> Bool {
        guard let pressedButton else { return true }
        guard !releasing else { return false }
        revision &+= 1
        releasePending = true
        releasing = true
        defer { releasing = false }
        guard perform(.mouseButton(pressedButton, pressed: false)) else { return false }
        self.pressedButton = nil
        releasePending = false
        return true
    }
}
