import Foundation

enum MouseButton: Int, CaseIterable, Codable, Sendable {
    case left = 0
    case right = 1
    case middle = 2

    var title: String {
        switch self {
        case .left: return "Left button"
        case .right: return "Right button"
        case .middle: return "Middle button"
        }
    }
}
