import CoreGraphics
import Foundation
import Testing
@testable import AirPointer

@Suite("Gesture calibration behavior")
struct GestureCalibrationBehaviorTests {

	@Test func calibratorProducesThresholdsBetweenOpenAndClosedSamples() throws {
		let base = Date(timeIntervalSinceReferenceDate: 60_000)
		let samples = [
			sample(.openHand, at: base, pose: .open),
			sample(.openHand, at: base.addingTimeInterval(0.1), pose: .open),
			sample(.pinch, at: base.addingTimeInterval(0.2), pose: .pinch),
			sample(.pinch, at: base.addingTimeInterval(0.3), pose: .pinch),
			sample(.fist, at: base.addingTimeInterval(0.4), pose: .fist),
			sample(.fist, at: base.addingTimeInterval(0.5), pose: .fist),
		]

		let profile = try GestureCalibrator.calibrate(
			samples: samples,
			generatedAt: Date(timeIntervalSinceReferenceDate: 70_000)
		)

		#expect(profile.openHandSamples == 2)
		#expect(profile.pinchSamples == 2)
		#expect(profile.fistSamples == 2)
		#expect(profile.pinchThresholdOn > 0.002)
		#expect(profile.pinchThresholdOn < profile.pinchThresholdOff)
		#expect(profile.pinchThresholdOff < 0.57)
		#expect(profile.fistThresholdOn > 0)
		#expect(profile.fistThresholdOn < profile.fistThresholdOff)
	}

	@Test func calibratorRejectsMissingPoseGroups() {
		let base = Date(timeIntervalSinceReferenceDate: 80_000)
		let samples = [
			sample(.openHand, at: base, pose: .open),
			sample(.pinch, at: base.addingTimeInterval(0.1), pose: .pinch),
		]

		do {
			_ = try GestureCalibrator.calibrate(samples: samples)
			Issue.record("Expected calibration to reject missing fist samples")
		} catch let error as GestureCalibrationError {
			#expect(error == .missingSamples(.fist))
		} catch {
			Issue.record("Unexpected error: \(error)")
		}
	}
}

private func sample(
	_ calibrationPose: GestureCalibrationPose,
	at timestamp: Date,
	pose: SyntheticHandPose
) -> GestureCalibrationSample {
	GestureCalibrationSample(
		pose: calibrationPose,
		handSide: .right,
		airFrame: frame(at: timestamp, side: .right, pose: pose)
	)
}
