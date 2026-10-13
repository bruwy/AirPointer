import Foundation

enum AirGesture: String, CaseIterable {
	case pinkyUp = "PinkyUp"
	case pinchDoubleRight = "PinchDoubleRight"
	case fistRight = "FistRight"

	var displayName: String {
		switch self {
		case .pinkyUp: return "Pinky Up"
		case .pinchDoubleRight: return "Double Pinch Right"
		case .fistRight: return "Right Fist"
		}
	}

	var intent: AirIntent {
		switch self {
		case .pinkyUp: return .toggleMute
		case .pinchDoubleRight: return .nextSlide
		case .fistRight: return .previousSlide
		}
	}
}

struct AirGestureEvent {
	let gesture: AirGesture
	let intent: AirIntent
	let hand: AirHandSide?
	let timestamp: Date
}
