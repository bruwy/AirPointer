import Foundation

enum AirIntent: String, CaseIterable {
    case nextSlide = "NextSlide"
    case previousSlide = "PrevSlide"
    case toggleMute = "ToggleMute"

    var displayName: String {
        switch self {
        case .nextSlide: return "Next Slide"
        case .previousSlide: return "Previous Slide"
        case .toggleMute: return "Toggle Mute"
        }
    }
}
