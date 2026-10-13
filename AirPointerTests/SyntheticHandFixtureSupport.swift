import CoreGraphics
import Foundation
import Vision
@testable import AirPointer

enum SyntheticHandPose {
	case open
	case pinch
	case fist
}

func frame(at timestamp: Date, side: AirHandSide, pose: SyntheticHandPose) -> AirFrame {
	AirFrame(
		timestamp: timestamp,
		hands: [handSnapshot(side: side, pose: pose)]
	)
}

func handSnapshot(side: AirHandSide, pose: SyntheticHandPose) -> AirHandSnapshot {
	let joints = syntheticJoints(for: pose)
	return AirHandSnapshot(side: side, joints: joints, wrist: joints[.wrist])
}

func syntheticJoints(
	for pose: SyntheticHandPose
) -> [VNHumanHandPoseObservation.JointName: CGPoint] {
	var joints: [VNHumanHandPoseObservation.JointName: CGPoint] = [
		.wrist: CGPoint(x: 0, y: 0),
		.middleMCP: CGPoint(x: 0, y: 1),
		.indexMCP: CGPoint(x: -0.10, y: 0),
		.littleMCP: CGPoint(x: 0.10, y: 0),
		.middleTip: CGPoint(x: 0, y: 0.65),
		.ringTip: CGPoint(x: 0.08, y: 0.55),
		.littleTip: CGPoint(x: 0.12, y: 0.50),
		.littlePIP: CGPoint(x: 0.10, y: 0.30),
	]

	switch pose {
	case .open:
		joints[.thumbTip] = CGPoint(x: -0.25, y: 0)
		joints[.indexTip] = CGPoint(x: 0.50, y: 0)
	case .pinch:
		joints[.thumbTip] = CGPoint(x: 0.20, y: 0)
		joints[.indexTip] = CGPoint(x: 0.25, y: 0)
	case .fist:
		joints[.thumbTip] = CGPoint(x: 0.01, y: 0.01)
		joints[.indexTip] = CGPoint(x: 0.01, y: 0.02)
		joints[.middleTip] = CGPoint(x: 0, y: 0.02)
		joints[.ringTip] = CGPoint(x: -0.01, y: 0.02)
		joints[.littleTip] = CGPoint(x: -0.02, y: 0.01)
	}

	return joints
}
