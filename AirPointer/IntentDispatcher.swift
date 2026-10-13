import Foundation
import AppKit

struct Shortcut {
    let keyCode: CGKeyCode
    let modifiers: NSEvent.ModifierFlags
}

enum SystemAction {
    case shortcut(Shortcut)
    case scroll(deltaX: Int32, deltaY: Int32)
    case volume(delta: Float)
    case moveMouseBy(CGVector)
    case clickMouse(buttonRight: Bool)
}

enum CommandDeliveryStatus: String {
    case idle = "No command yet"
    case blockedAccessibility = "Blocked: Accessibility required"
    case unmapped = "No action in this profile"
    case submitted = "Submitted to macOS"
    case failed = "Command submission failed"
    case diagnostic = "Diagnostic only: no commands sent"
    case permissionChanged = "Permissions changed: gesture cancelled"
}

protocol SystemActionPerforming {
    @discardableResult
    func perform(_ action: SystemAction) -> Bool
}

struct LiveSystemActionPerformer: SystemActionPerforming {
    @discardableResult
    func perform(_ action: SystemAction) -> Bool {
        switch action {
        case .shortcut(let shortcut):
            return KeyboardController.send(shortcut)
        case .scroll(let deltaX, let deltaY):
            return MouseController.scroll(deltaX: deltaX, deltaY: deltaY)
        case .volume(let delta):
            return SystemVolumeController.adjustOutputVolume(delta: delta)
        case .moveMouseBy(let delta):
            return MouseController.move(by: delta)
        case .clickMouse(let right):
            return MouseController.click(buttonRight: right)
        }
    }
}

enum SystemVolumeController {
	@discardableResult
	static func adjustOutputVolume(delta: Float) -> Bool {
		guard delta.isFinite else { return false }
		let step = Int((min(max(delta, -2), 2) * 50).rounded())
        guard step != 0 else { return true }

        let scriptSource = """
        set currentVolume to output volume of (get volume settings)
        set newVolume to currentVolume + \(step)
        if newVolume < 0 then set newVolume to 0
        if newVolume > 100 then set newVolume to 100
        set volume output volume newVolume
        """

        guard let script = NSAppleScript(source: scriptSource) else { return false }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        return error == nil
    }
}

protocol AirProfile {
    var name: String { get }
    func action(for intent: AirIntent) -> SystemAction?
}

enum AirProfileKind: String, CaseIterable {
    case presentation
    case call
    case deepwork

    var title: String {
        switch self {
        case .presentation: return "Presentation"
        case .call: return "Call"
        case .deepwork: return "Deepwork"
        }
    }
}

struct PresentationProfile: AirProfile {
    let name = "Presentation"

    func action(for intent: AirIntent) -> SystemAction? {
        switch intent {
        case .nextSlide:
            return .shortcut(Shortcut(keyCode: KeyCode.rightArrow, modifiers: []))
        case .previousSlide:
            return .shortcut(Shortcut(keyCode: KeyCode.leftArrow, modifiers: []))
        case .toggleMute:
            // Default to Zoom mute shortcut; tweak per app later.
            return .shortcut(Shortcut(keyCode: KeyCode.a, modifiers: [.command, .shift]))
        }
    }
}

struct CallProfile: AirProfile {
    let name = "Call"

    func action(for intent: AirIntent) -> SystemAction? {
        switch intent {
        case .toggleMute:
            // Zoom default; adjust for Meet/Teams as needed.
            return .shortcut(Shortcut(keyCode: KeyCode.a, modifiers: [.command, .shift]))
        case .nextSlide, .previousSlide:
            return nil
        }
    }
}

struct DeepworkProfile: AirProfile {
    let name = "Deepwork"
    
    // Deepwork acts differently: it uses continuous gestures (scroll, scrub)
    // which are handled by the Gesture Recognition engine directly triggering Mouse events,
    // rather than discrete Intents. 
    // However, we can map discrete intents if needed (e.g. Play/Pause).
    
    func action(for intent: AirIntent) -> SystemAction? {
        switch intent {
        case .toggleMute:
           // Logic: Fist -> Play/Pause
           // We might need a new Intent for PlayPause, or reuse toggleMute with different mapping?
           // For now, let's map toggleMute (Pinky Up) to standard Mute even in Deepwork?
           // User guide says: "hand closing -> play/pause". "rotary -> volume".
           // Pinky Up -> "Modes"?
           return nil // Deepwork relies mostly on physics gestures, handled separately.
        default:
            return nil
        }
    }
}

final class IntentDispatcher {
    private var profile: AirProfile
    private let performer: SystemActionPerforming

    init(
        profile: AirProfile = PresentationProfile(),
        performer: SystemActionPerforming = LiveSystemActionPerformer()
    ) {
        self.profile = profile
        self.performer = performer
    }

    func setProfile(kind: AirProfileKind) {
        switch kind {
        case .presentation:
            profile = PresentationProfile()
        case .call:
            profile = CallProfile()
        case .deepwork:
            profile = DeepworkProfile()
        }
    }

    @discardableResult
    func handle(intent: AirIntent) -> Bool {
        guard let action = action(for: intent) else { return false }
        return performer.perform(action)
    }

    func action(for intent: AirIntent) -> SystemAction? {
        profile.action(for: intent)
    }
}
