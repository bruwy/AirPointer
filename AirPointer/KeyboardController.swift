import AppKit

enum KeyCode {
    static let leftArrow: CGKeyCode = 123
    static let rightArrow: CGKeyCode = 124
    static let a: CGKeyCode = 0
    static let d: CGKeyCode = 2
    static let m: CGKeyCode = 46
}

enum KeyboardController {
    @discardableResult
    static func send(_ shortcut: Shortcut) -> Bool {
        guard CGPreflightPostEventAccess() else { return false }
        let flags = CGEventFlags(rawValue: UInt64(shortcut.modifiers.rawValue))
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: shortcut.keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: shortcut.keyCode, keyDown: false)
        else { return false }

        down.flags = flags
        down.post(tap: .cghidEventTap)

        up.flags = flags
        up.post(tap: .cghidEventTap)

        return true
    }
}
