import AppKit
import CoreGraphics

enum MouseController {
    
    private static func currentFlippedLocation() -> CGPoint? {
        CGEvent(source: nil)?.location
    }

    /// Relative movement always starts from the live Quartz cursor.
    @discardableResult
    static func move(by delta: CGVector) -> Bool {
        guard CGPreflightPostEventAccess(), let current = currentFlippedLocation(),
              delta.dx.isFinite, delta.dy.isFinite,
              hypot(delta.dx, delta.dy) <= 96.001 else { return false }
        let screens = NSScreen.screens.compactMap { screen -> CGRect? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return CGDisplayBounds(number.uint32Value)
        }
        guard let point = relativePoint(current: current, delta: delta, screens: screens),
              let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                                  mouseCursorPosition: point, mouseButton: .left) else { return false }
        event.setIntegerValueField(.mouseEventDeltaX, value: Int64((point.x - current.x).rounded()))
        event.setIntegerValueField(.mouseEventDeltaY, value: Int64((point.y - current.y).rounded()))
        event.post(tap: .cghidEventTap)
        return true
    }

    static func relativePoint(current: CGPoint, delta: CGVector, screens: [CGRect]) -> CGPoint? {
        guard current.x.isFinite, current.y.isFinite, delta.dx.isFinite, delta.dy.isFinite else { return nil }
        let proposed = CGPoint(x: current.x + delta.dx, y: current.y + delta.dy)
        let validScreens = screens.filter { $0.width > 1 && $0.height > 1 && !$0.isInfinite && !$0.isNull }
        if validScreens.contains(where: { $0.contains(proposed) }) { return proposed }
        return validScreens.map { frame in
            CGPoint(x: min(max(proposed.x, frame.minX), frame.maxX - 1),
                    y: min(max(proposed.y, frame.minY), frame.maxY - 1))
        }.min { a, b in
            hypot(a.x - proposed.x, a.y - proposed.y) < hypot(b.x - proposed.x, b.y - proposed.y)
        }
    }

    /// Construct both events first and post one balanced pair at one position.
    /// There is no deferred mouse-up that a lost hand/mode switch could cancel.
    @discardableResult
    static func click(buttonRight: Bool = false) -> Bool {
        guard CGPreflightPostEventAccess(),
              let point = currentFlippedLocation(),
              let pair = clickEvents(buttonRight: buttonRight, at: point) else { return false }
        pair.0.post(tap: .cghidEventTap)
        pair.1.post(tap: .cghidEventTap)
        return true
    }

    // Kept separate so tests inspect event construction without posting events.
    static func clickEvents(buttonRight: Bool, at point: CGPoint) -> (CGEvent, CGEvent)? {
        guard point.x.isFinite, point.y.isFinite else { return nil }
        let button: CGMouseButton = buttonRight ? .right : .left
        guard let down = CGEvent(mouseEventSource: nil,
                                 mouseType: buttonRight ? .rightMouseDown : .leftMouseDown,
                                 mouseCursorPosition: point, mouseButton: button),
              let up = CGEvent(mouseEventSource: nil,
                               mouseType: buttonRight ? .rightMouseUp : .leftMouseUp,
                               mouseCursorPosition: point, mouseButton: button) else { return nil }
        down.setIntegerValueField(.mouseEventClickState, value: 1)
        up.setIntegerValueField(.mouseEventClickState, value: 1)
        return (down, up)
    }

    /// Pressionar botão do mouse (esquerdo por padrão, ou direito se buttonRight=true)
    @discardableResult
    static func mouseDown(buttonRight: Bool = false) -> Bool {
        guard CGPreflightPostEventAccess() else { return false }
        guard let clickLocation = currentFlippedLocation() else { return false }
        let type: CGEventType = buttonRight ? .rightMouseDown : .leftMouseDown
        let btn: CGMouseButton = buttonRight ? .right : .left
        if let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: clickLocation, mouseButton: btn) {
            e.setIntegerValueField(.mouseEventClickState, value: Int64(1))
            e.post(tap: CGEventTapLocation.cghidEventTap)
            return true
        }
        return false
    }
    
    /// Soltar botão do mouse (esquerdo por padrão, ou direito se buttonRight=true)
    @discardableResult
    static func mouseUp(buttonRight: Bool = false) -> Bool {
        guard CGPreflightPostEventAccess() else { return false }
        guard let clickLocation = currentFlippedLocation() else { return false }
        let type: CGEventType = buttonRight ? .rightMouseUp : .leftMouseUp
        let btn: CGMouseButton = buttonRight ? .right : .left
        if let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: clickLocation, mouseButton: btn) {
            e.setIntegerValueField(.mouseEventClickState, value: Int64(1))
            e.post(tap: CGEventTapLocation.cghidEventTap)
            return true
        }
        return false
    }
    
    /// Duplo clique com clickCount correto
    @discardableResult
    static func doubleClick(buttonRight: Bool = false) -> Bool {
        guard CGPreflightPostEventAccess() else { return false }
        guard let clickLocation = currentFlippedLocation() else { return false }
        let downType: CGEventType = buttonRight ? .rightMouseDown : .leftMouseDown
        let upType: CGEventType = buttonRight ? .rightMouseUp : .leftMouseUp
        let btn: CGMouseButton = buttonRight ? .right : .left
        for i in 1...2 {
            guard let d = CGEvent(mouseEventSource: nil, mouseType: downType, mouseCursorPosition: clickLocation, mouseButton: btn),
                  let u = CGEvent(mouseEventSource: nil, mouseType: upType, mouseCursorPosition: clickLocation, mouseButton: btn)
            else { return false }

            d.setIntegerValueField(.mouseEventClickState, value: Int64(i))
            d.post(tap: CGEventTapLocation.cghidEventTap)

            u.setIntegerValueField(.mouseEventClickState, value: Int64(i))
            u.post(tap: CGEventTapLocation.cghidEventTap)
        }
        return true
    }

    /// Scroll em pixels (positivo = para cima/direita)
    @discardableResult
    static func scroll(deltaX: Int32, deltaY: Int32) -> Bool {
        guard CGPreflightPostEventAccess() else { return false }
        if let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: deltaY, wheel2: deltaX, wheel3: 0) {
            e.post(tap: CGEventTapLocation.cghidEventTap)
            return true
        }
        return false
    }
}
