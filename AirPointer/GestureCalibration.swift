import CoreGraphics
import Foundation
import Vision

nonisolated enum GestureCalibrationPose: String, CaseIterable, Codable, Sendable {
	case openHand
	case pinch
	case fist
}

nonisolated struct GestureCalibrationSample: Codable, Equatable, Sendable {
	let pose: GestureCalibrationPose
	let handSide: AirHandSide
	let frame: AirFrameFixture

	init(pose: GestureCalibrationPose, handSide: AirHandSide, frame: AirFrameFixture) {
		self.pose = pose
		self.handSide = handSide
		self.frame = frame
	}

	init(pose: GestureCalibrationPose, handSide: AirHandSide, airFrame: AirFrame) {
		self.init(
			pose: pose,
			handSide: handSide,
			frame: AirFrameFixture(frame: airFrame, relativeTo: airFrame.timestamp)
		)
	}

	func handSnapshot(startingAt startDate: Date = Date()) -> AirHandSnapshot? {
		frame
			.airFrame(startingAt: startDate)
			.hands
			.first(where: { $0.side == handSide })
	}
}

nonisolated struct GestureCalibrationProfile: Codable, Equatable, Sendable {
	let schemaVersion: Int
	let generatedAt: Date
	let openHandSamples: Int
	let pinchSamples: Int
	let fistSamples: Int
	let pinchThresholdOn: CGFloat
	let pinchThresholdOff: CGFloat
	let fistThresholdOn: CGFloat
	let fistThresholdOff: CGFloat

	static let currentSchemaVersion = 1
}

enum GestureCalibrationError: Error, Equatable {
	case missingSamples(GestureCalibrationPose)
	case insufficientMetricSeparation(String)
}

enum GestureCalibrator {
	static func calibrate(
		samples: [GestureCalibrationSample],
		generatedAt: Date = Date()
	) throws -> GestureCalibrationProfile {
		let openPinch = metricValues(samples: samples, pose: .openHand) {
			HandPoseMetrics.pinchDistanceNormalized(from: $0.joints)
		}
		let pinch = metricValues(samples: samples, pose: .pinch) {
			HandPoseMetrics.pinchDistanceNormalized(from: $0.joints)
		}
		let openFist = metricValues(samples: samples, pose: .openHand) {
			HandPoseMetrics.fistMetric(from: $0.joints)
		}
		let fist = metricValues(samples: samples, pose: .fist) {
			HandPoseMetrics.fistMetric(from: $0.joints)
		}

		guard !openPinch.isEmpty else { throw GestureCalibrationError.missingSamples(.openHand) }
		guard !pinch.isEmpty else { throw GestureCalibrationError.missingSamples(.pinch) }
		guard !fist.isEmpty else { throw GestureCalibrationError.missingSamples(.fist) }
		guard !openFist.isEmpty else { throw GestureCalibrationError.missingSamples(.openHand) }

		let openPinchMean = mean(openPinch)
		let pinchMean = mean(pinch)
		let openFistMean = mean(openFist)
		let fistMean = mean(fist)

		guard openPinchMean > pinchMean else {
			throw GestureCalibrationError.insufficientMetricSeparation("pinch")
		}
		guard openFistMean > fistMean else {
			throw GestureCalibrationError.insufficientMetricSeparation("fist")
		}

		let pinchGap = openPinchMean - pinchMean
		let fistGap = openFistMean - fistMean

		return GestureCalibrationProfile(
			schemaVersion: GestureCalibrationProfile.currentSchemaVersion,
			generatedAt: generatedAt,
			openHandSamples: openPinch.count,
			pinchSamples: pinch.count,
			fistSamples: fist.count,
			pinchThresholdOn: pinchMean + pinchGap * 0.35,
			pinchThresholdOff: pinchMean + pinchGap * 0.55,
			fistThresholdOn: fistMean + fistGap * 0.35,
			fistThresholdOff: fistMean + fistGap * 0.55
		)
	}

	private static func metricValues(
		samples: [GestureCalibrationSample],
		pose: GestureCalibrationPose,
		metric: (AirHandSnapshot) -> CGFloat?
	) -> [CGFloat] {
		samples
			.filter { $0.pose == pose }
			.compactMap { sample in
				guard let hand = sample.handSnapshot() else { return nil }
				return metric(hand)
			}
	}

	private static func mean(_ values: [CGFloat]) -> CGFloat {
		values.reduce(0, +) / CGFloat(values.count)
	}
}
