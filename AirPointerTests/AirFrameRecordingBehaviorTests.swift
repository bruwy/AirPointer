import CoreGraphics
import Foundation
import Testing
import Vision
@testable import AirPointer

@MainActor
@Suite("AirFrame recording and replay behavior")
struct AirFrameRecordingBehaviorTests {

	@Test func recordingRoundTripsThroughJSON() throws {
		let base = Date(timeIntervalSinceReferenceDate: 10_000)
		let frames = [
			frame(at: base, side: .right, pose: .open),
			frame(at: base.addingTimeInterval(0.1), side: .right, pose: .pinch),
		]
		let recording = AirFrameRecording(
			frames: frames,
			label: "right-pinch",
			createdAt: Date(timeIntervalSinceReferenceDate: 20_000)
		)

		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .iso8601
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601

		let data = try encoder.encode(recording)
		let decoded = try decoder.decode(AirFrameRecording.self, from: data)

		#expect(decoded == recording)
		#expect(abs(decoded.frames[0].offsetSeconds - 0) < 0.0001)
		#expect(abs(decoded.frames[1].offsetSeconds - 0.1) < 0.0001)
	}

	@Test func recorderKeepsRelativeFrameOffsets() {
		let recorder = AirFrameRecorder()
		let base = Date(timeIntervalSinceReferenceDate: 30_000)

		recorder.start()
		recorder.append(frame(at: base, side: .left, pose: .open))
		recorder.append(frame(at: base.addingTimeInterval(0.25), side: .left, pose: .pinch))

		let recording = recorder.stop(label: "left-pinch")

		#expect(!recorder.isRecording)
		#expect(recording.frames.count == 2)
		#expect(recording.frames[0].offsetSeconds == 0)
		#expect(recording.frames[1].offsetSeconds == 0.25)
	}

	@Test func replayerCanDriveRecognizerWithoutCamera() {
		let recording = AirFrameRecording(
			frames: doublePinchFrames(side: .right),
			label: "right-double-pinch",
			createdAt: Date(timeIntervalSinceReferenceDate: 40_000)
		)
		let recognizer = AirGestureRecognizer()
		let replayer = AirFrameReplayer(recording: recording)

		let events = replayer.replay(
			into: recognizer,
			startingAt: Date(timeIntervalSinceReferenceDate: 50_000)
		)

		#expect(events.map(\.gesture).contains(.pinchDoubleRight))
		#expect(events.map(\.intent).contains(.nextSlide))
	}
}

private func doublePinchFrames(side: AirHandSide) -> [AirFrame] {
	let base = Date(timeIntervalSinceReferenceDate: 1_000)
	let timeline: [(TimeInterval, SyntheticHandPose)] = [
		(0.00, .pinch),
		(0.05, .pinch),
		(0.12, .open),
		(0.17, .open),
		(0.30, .pinch),
		(0.35, .pinch),
		(0.40, .pinch),
		(0.45, .pinch),
		(0.55, .open),
	]

	return timeline.map { offset, pose in
		frame(at: base.addingTimeInterval(offset), side: side, pose: pose)
	}
}
