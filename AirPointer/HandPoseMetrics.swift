import CoreGraphics
import Foundation
import Vision

enum HandPoseMetrics {
	static func distanceSquared(_ p1: CGPoint, _ p2: CGPoint) -> CGFloat {
		let dx = p1.x - p2.x
		let dy = p1.y - p2.y
		return dx * dx + dy * dy
	}

	static func handScaleSquared(
		from joints: [VNHumanHandPoseObservation.JointName: CGPoint]
	) -> CGFloat? {
		if let wrist = joints[.wrist], let middleMCP = joints[.middleMCP] {
			let scale = distanceSquared(wrist, middleMCP)
			if scale.isFinite && scale > 1e-6 { return scale }
		}

		if let indexMCP = joints[.indexMCP], let littleMCP = joints[.littleMCP] {
			let scale = distanceSquared(indexMCP, littleMCP)
			if scale.isFinite && scale > 1e-6 { return scale }
		}

		return nil
	}

	static func pinchDistanceNormalized(
		from joints: [VNHumanHandPoseObservation.JointName: CGPoint]
	) -> CGFloat? {
		guard let thumb = joints[.thumbTip],
			let index = joints[.indexTip],
			let scaleSquared = handScaleSquared(from: joints)
		else { return nil }

		let distance = distanceSquared(thumb, index)
		guard distance.isFinite else { return nil }
		return distance / scaleSquared
	}

	static func fistMetric(
		from joints: [VNHumanHandPoseObservation.JointName: CGPoint]
	) -> CGFloat? {
		guard let indexMCP = joints[.indexMCP], let littleMCP = joints[.littleMCP] else {
			return nil
		}

		let palmCenter = CGPoint(
			x: (indexMCP.x + littleMCP.x) / 2,
			y: (indexMCP.y + littleMCP.y) / 2
		)
		let scaleSquared = distanceSquared(indexMCP, littleMCP)
		guard scaleSquared.isFinite && scaleSquared > 1e-6 else { return nil }

		let tips: [VNHumanHandPoseObservation.JointName] = [
			.indexTip, .middleTip, .ringTip, .littleTip,
		]

		var accumulated: CGFloat = 0
		var count = 0

		for tip in tips {
			guard let point = joints[tip] else { return nil }
			let distance = distanceSquared(point, palmCenter)
			guard distance.isFinite else { return nil }
			accumulated += distance
			count += 1
		}

		return (accumulated / CGFloat(count)) / scaleSquared
	}

	static func extensionRatio(
		for tip: VNHumanHandPoseObservation.JointName,
		from joints: [VNHumanHandPoseObservation.JointName: CGPoint]
	) -> CGFloat? {
		guard let wrist = joints[.wrist],
			let tipPoint = joints[tip],
			let scaleSquared = handScaleSquared(from: joints)
		else { return nil }

		let distance = distanceSquared(wrist, tipPoint)
		guard distance.isFinite else { return nil }
		return sqrt(distance / scaleSquared)
	}

	static func isPinkyUpPose(
		joints: [VNHumanHandPoseObservation.JointName: CGPoint],
		pinkyExtendedMin: CGFloat,
		othersMax: CGFloat,
		thumbMax: CGFloat,
		verticalLiftMin: CGFloat
	) -> Bool {
		guard let littleTip = joints[.littleTip],
			let littlePIP = joints[.littlePIP],
			let littleExtension = extensionRatio(for: .littleTip, from: joints),
			let indexExtension = extensionRatio(for: .indexTip, from: joints),
			let middleExtension = extensionRatio(for: .middleTip, from: joints),
			let ringExtension = extensionRatio(for: .ringTip, from: joints),
			let thumbExtension = extensionRatio(for: .thumbTip, from: joints)
		else { return false }

		return littleExtension >= pinkyExtendedMin
			&& indexExtension <= othersMax
			&& middleExtension <= othersMax
			&& ringExtension <= othersMax
			&& (littleTip.y - littlePIP.y) >= verticalLiftMin
			&& thumbExtension <= thumbMax
	}
}
