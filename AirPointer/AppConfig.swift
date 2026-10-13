import Foundation
import CoreGraphics

struct AppConfig {
	// Overlay defaults
	static var showSkeletonOverlay: Bool = true
	static var showHUD: Bool = true

	struct GestureTuning {
		static let mirrorInput: Bool = true
		static let maximumFrameGap: TimeInterval = 0.25
		
		static let pinkyUpHold: TimeInterval = 0.35
		static let pinkyUpMotionTolerance: CGFloat = 0.05
		static let pinkyUpCooldown: TimeInterval = 1.0
		static let minPinchDistanceForPinky: CGFloat = 0.12
		static let pinkyExtendedMin: CGFloat = 1.25
		static let pinkyOthersMax: CGFloat = 1.08
		static let pinkyThumbMax: CGFloat = 1.25
		static let pinkyVerticalLiftMin: CGFloat = 0.04
		
		static let pinchTapWindow: TimeInterval = 0.85
		static let pinchTapCount: Int = 2
		static let pinchCooldown: TimeInterval = 0.9
		static let pinchTapMinHold: TimeInterval = 0.03
		static let pinchTapMaxHold: TimeInterval = 0.90
		static let pinchTapMinSeparation: TimeInterval = 0.12
		static let presentationFistHold: TimeInterval = 0.25
		static let presentationFistRearmHold: TimeInterval = 0.15
		
		// New Centralized Configs
		static let fistThresholdOn: CGFloat = 0.11
		static let fistThresholdOff: CGFloat = 0.16 // +0.05 hysteresis
		static let fistFramesOn: Int = 3
		static let fistFramesOff: Int = 2
		
		static let pinchThresholdOn: CGFloat = 0.082
		static let pinchThresholdOff: CGFloat = 0.112
		static let pinchFramesOn: Int = 2
		static let pinchFramesOff: Int = 1
		
		static let smoothingAlpha: CGFloat = 0.45

		static let pointingIndexMin: CGFloat = 1.35
		static let pointingMiddleMax: CGFloat = 1.05
		static let pointingRingMax: CGFloat = 1.10
		static let pointingFramesOn: Int = 3
		static let pointingFramesOff: Int = 2

		static let pointerSmoothingAlpha: CGFloat = 0.40
		static let pointerGraceFrames: Int = 3
	}

    struct MouseTuning {
        static let extendedMin: CGFloat = 1.35
        static let curledMax: CGFloat = 1.05
        static let poseHold: TimeInterval = 0.20
        static let neutralHold: TimeInterval = 0.12
        static let minimumStableFrames = 3
    }

	struct ScrollTuning {
		static let neutralDisplacement: CGFloat = 0.02
		static let fullSpeedDisplacement: CGFloat = 0.20
		static let maximumPixelsPerSecond: CGFloat = 900
		static let maximumEventInterval: TimeInterval = 1.0 / 15.0
	}

	struct GestureDefaults {
		static let enableNext: Bool = true
		static let enablePrev: Bool = true
		static let enableMute: Bool = true
	}
}
