import Foundation
import Combine
import Vision
import AVFoundation
import CoreGraphics

final class HandTracker: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {

	// MARK: - Published State
	@Published var handJoints: [String: [VNHumanHandPoseObservation.JointName: CGPoint]] = [:]
	private(set) var observationTimestamp: Date?

	// MARK: - Internal Dependencies
	private let request = VNDetectHumanHandPoseRequest()
	private let sequenceHandler = VNSequenceRequestHandler()
	public let session = AVCaptureSession()
	private let videoOutput = AVCaptureVideoDataOutput()
	private let sessionQueue = DispatchQueue(label: "com.airpointer.handtracker.session", qos: .userInitiated)
	private let cameraQueue = DispatchQueue(label: "com.airpointer.handtracker.camera", qos: .userInitiated)
	private let configuresCamera: Bool
	private let deliveryLock = NSLock()
	private var deliveryRevision = 0
	private var activeCaptureRevision: Int?

	// MARK: - Settings
	public var invertHandedness: Bool = true

	// MARK: - Tracking State
	private struct CandidateHand {
		let wrist: CGPoint
		let joints: [VNHumanHandPoseObservation.JointName: CGPoint]
	}

	private struct TrackedHandState {
		var smoothedJoints: [VNHumanHandPoseObservation.JointName: CGPoint] = [:]
		var lastWrist: CGPoint?
		var missingFrames: Int = 0
	}

	private enum TrackingConfig {
		static let wristConfidence: VNConfidence = 0.35
		static let jointConfidence: VNConfidence = 0.22
		static let minimumJointCount: Int = 8
		static let smoothingAlpha: CGFloat = 0.42
		static let maxJointJump: CGFloat = 0.20
		static let singleHandSnapDistance: CGFloat = 0.28
		static let lostHandGraceFrames: Int = 4
		static let targetFPS: Double = 30.0
	}

	private var trackedStates: [String: TrackedHandState] = [
		"left": TrackedHandState(),
		"right": TrackedHandState(),
	]

	private static let leftKey = "left"
	private static let rightKey = "right"
	private static let sideOrder = [leftKey, rightKey]

	// MARK: - Init & Setup
	override convenience init() {
		self.init(configuresCamera: true)
	}

	// Tests can exercise frame delivery without opening a capture device.
	init(configuresCamera: Bool) {
		self.configuresCamera = configuresCamera
		super.init()
		configureRequest()
		if configuresCamera { setupCamera() }
	}

	private func configureRequest() {
		request.maximumHandCount = 2
		request.preferBackgroundProcessing = false
		if let newestRevision = VNDetectHumanHandPoseRequest.supportedRevisions.max() {
			request.revision = newestRevision
		}
	}

	private func setupCamera() {
		session.beginConfiguration()
		if session.canSetSessionPreset(.vga640x480) {
			session.sessionPreset = .vga640x480
		}

		guard let captureDevice = AVCaptureDevice.default(
			.builtInWideAngleCamera, for: .video, position: .front),
			let deviceInput = try? AVCaptureDeviceInput(device: captureDevice)
		else {
			session.commitConfiguration()
			print("HandTracker: Falha ao acessar câmera frontal.")
			return
		}

		configureCaptureDevice(captureDevice)

		if session.canAddInput(deviceInput) {
			session.addInput(deviceInput)
		}

		videoOutput.videoSettings = [
			kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
		]
		videoOutput.alwaysDiscardsLateVideoFrames = true
		videoOutput.setSampleBufferDelegate(self, queue: cameraQueue)

		if session.canAddOutput(videoOutput) {
			session.addOutput(videoOutput)
		}

		if let connection = videoOutput.connection(with: .video),
			connection.isVideoMirroringSupported
		{
			connection.automaticallyAdjustsVideoMirroring = false
			connection.isVideoMirrored = false
		}

		session.commitConfiguration()
	}

	private func configureCaptureDevice(_ captureDevice: AVCaptureDevice) {
		do {
			try captureDevice.lockForConfiguration()
			defer { captureDevice.unlockForConfiguration() }

			let targetFPS = TrackingConfig.targetFPS
			if captureDevice.activeFormat.videoSupportedFrameRateRanges.contains(where: {
				$0.minFrameRate <= targetFPS && $0.maxFrameRate >= targetFPS
			}) {
				let frameDuration = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
				captureDevice.activeVideoMinFrameDuration = frameDuration
				captureDevice.activeVideoMaxFrameDuration = frameDuration
			}
		} catch {
			print("HandTracker: Não foi possível fixar frame rate: \(error.localizedDescription)")
		}
	}

	public func start() {
		let revision = advanceDeliveryRevision()
		guard configuresCamera else { return }
		sessionQueue.async { [weak self] in
			guard let self, self.activateCapture(revision: revision) else { return }
			if !self.session.isRunning { self.session.startRunning() }
		}
	}

	public func stop() {
		_ = advanceDeliveryRevision()
		guard configuresCamera else {
			publish([:])
			return
		}
		sessionQueue.async { [weak self] in
			guard let self else { return }
			if self.session.isRunning {
				self.session.stopRunning()
			}

			self.cameraQueue.sync {
				self.trackedStates = [
					Self.leftKey: TrackedHandState(),
					Self.rightKey: TrackedHandState(),
				]
			}
			self.publish([:])
		}
	}

	// MARK: - Capture Delegate
	func captureOutput(
		_ output: AVCaptureOutput,
		didOutput sampleBuffer: CMSampleBuffer,
		from connection: AVCaptureConnection
	) {
		guard let revision = captureRevision() else { return }
		// Stamp before Vision and main-queue delivery, not after their latency.
		let observationAt = Date()
		guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

		do {
			try sequenceHandler.perform([request], on: pixelBuffer, orientation: .up)
		} catch {
			publish([:], at: observationAt, revision: revision)
			return
		}

		let observations = request.results ?? []
		let assignedHands = assignHands(from: observations)
		var stabilized = stabilize(assignedHands)

		if invertHandedness {
			let left = stabilized[Self.leftKey]
			let right = stabilized[Self.rightKey]
			stabilized[Self.leftKey] = right
			stabilized[Self.rightKey] = left
		}

		publish(stabilized, at: observationAt, revision: revision)
	}

	private func assignHands(
		from observations: [VNHumanHandPoseObservation]
	) -> [String: CandidateHand] {
		var candidates: [CandidateHand] = []
		candidates.reserveCapacity(observations.count)

		for obs in observations {
			guard let recognizedPoints = try? obs.recognizedPoints(.all),
				let wrist = recognizedPoints[.wrist],
				wrist.confidence >= TrackingConfig.wristConfidence
			else {
				continue
			}

			var joints: [VNHumanHandPoseObservation.JointName: CGPoint] = [:]
			joints.reserveCapacity(Self.allJoints.count)

			for jointName in Self.allJoints {
				guard let point = recognizedPoints[jointName],
					point.confidence >= TrackingConfig.jointConfidence
				else {
					continue
				}
				joints[jointName] = point.location
			}

			guard joints.count >= TrackingConfig.minimumJointCount else { continue }
			candidates.append(CandidateHand(wrist: wrist.location, joints: joints))
		}

		guard !candidates.isEmpty else { return [:] }

		let ranked = Array(candidates.sorted { $0.joints.count > $1.joints.count }.prefix(2))
		guard !ranked.isEmpty else { return [:] }

		if ranked.count == 1 {
			let side = preferredSide(for: ranked[0].wrist)
			return [side: ranked[0]]
		}

		let first = ranked[0]
		let second = ranked[1]

		if let previousLeft = trackedStates[Self.leftKey]?.lastWrist,
			let previousRight = trackedStates[Self.rightKey]?.lastWrist
		{
			let keepCost = distanceSq(first.wrist, previousLeft) + distanceSq(second.wrist, previousRight)
			let swapCost = distanceSq(first.wrist, previousRight) + distanceSq(second.wrist, previousLeft)

			if keepCost <= swapCost {
				return [Self.leftKey: first, Self.rightKey: second]
			}
			return [Self.leftKey: second, Self.rightKey: first]
		}

		let sortedByX = [first, second].sorted { $0.wrist.x < $1.wrist.x }
		return [Self.leftKey: sortedByX[0], Self.rightKey: sortedByX[1]]
	}

	private func preferredSide(for wrist: CGPoint) -> String {
		let leftWrist = trackedStates[Self.leftKey]?.lastWrist
		let rightWrist = trackedStates[Self.rightKey]?.lastWrist

		switch (leftWrist, rightWrist) {
		case let (left?, right?):
			let distanceToLeft = sqrt(distanceSq(wrist, left))
			let distanceToRight = sqrt(distanceSq(wrist, right))

			if min(distanceToLeft, distanceToRight) <= TrackingConfig.singleHandSnapDistance {
				return distanceToLeft <= distanceToRight ? Self.leftKey : Self.rightKey
			}
		case let (left?, nil):
			if sqrt(distanceSq(wrist, left)) <= TrackingConfig.singleHandSnapDistance { return Self.leftKey }
		case let (nil, right?):
			if sqrt(distanceSq(wrist, right)) <= TrackingConfig.singleHandSnapDistance { return Self.rightKey }
		default:
			break
		}

		return wrist.x < 0.5 ? Self.leftKey : Self.rightKey
	}

	private func stabilize(
		_ assigned: [String: CandidateHand]
	) -> [String: [VNHumanHandPoseObservation.JointName: CGPoint]] {
		var out: [String: [VNHumanHandPoseObservation.JointName: CGPoint]] = [:]

		for side in Self.sideOrder {
			if let candidate = assigned[side] {
				let smoothed = smoothJoints(candidate.joints, for: side)
				out[side] = smoothed
				continue
			}

			var state = trackedStates[side] ?? TrackedHandState()
			state.missingFrames += 1
			// Retain identity briefly, but never recognize commands from stale joints.
			if state.missingFrames > TrackingConfig.lostHandGraceFrames {
				state.smoothedJoints = [:]
				state.lastWrist = nil
			}
			trackedStates[side] = state
		}

		return out
	}

	private func smoothJoints(
		_ joints: [VNHumanHandPoseObservation.JointName: CGPoint],
		for side: String
	) -> [VNHumanHandPoseObservation.JointName: CGPoint] {
		var state = trackedStates[side] ?? TrackedHandState()
		var smoothed: [VNHumanHandPoseObservation.JointName: CGPoint] = [:]
		smoothed.reserveCapacity(joints.count)

		for (jointName, current) in joints {
			guard let previous = state.smoothedJoints[jointName] else {
				smoothed[jointName] = current
				continue
			}

			let bounded = clampJump(from: previous, to: current, maxDistance: TrackingConfig.maxJointJump)
			let alpha = TrackingConfig.smoothingAlpha
			let filtered = CGPoint(
				x: previous.x + (bounded.x - previous.x) * alpha,
				y: previous.y + (bounded.y - previous.y) * alpha
			)
			smoothed[jointName] = filtered
		}

		state.smoothedJoints = smoothed
		state.lastWrist = smoothed[.wrist] ?? state.lastWrist
		state.missingFrames = 0
		trackedStates[side] = state

		return smoothed
	}

	private func clampJump(from previous: CGPoint, to current: CGPoint, maxDistance: CGFloat) -> CGPoint {
		let dx = current.x - previous.x
		let dy = current.y - previous.y
		let dist = hypot(dx, dy)
		guard dist > maxDistance, dist > 0 else { return current }

		let ratio = maxDistance / dist
		return CGPoint(
			x: previous.x + dx * ratio,
			y: previous.y + dy * ratio
		)
	}

    /// Mode/toggle/permission transitions invalidate observations already in
    /// Vision or the main queue without stopping/reconfiguring the camera.
    func invalidatePendingObservations() {
        deliveryLock.lock(); defer { deliveryLock.unlock() }
        deliveryRevision &+= 1
        if activeCaptureRevision != nil { activeCaptureRevision = deliveryRevision }
    }

	private func advanceDeliveryRevision() -> Int {
		deliveryLock.lock(); defer { deliveryLock.unlock() }
		deliveryRevision &+= 1
		activeCaptureRevision = nil
		return deliveryRevision
	}

	private func activateCapture(revision: Int) -> Bool {
		deliveryLock.lock(); defer { deliveryLock.unlock() }
		guard revision == deliveryRevision else { return false }
		activeCaptureRevision = revision
		return true
	}

	private func captureRevision() -> Int? {
		deliveryLock.lock(); defer { deliveryLock.unlock() }
		return activeCaptureRevision
	}

	private func currentDeliveryRevision() -> Int {
		deliveryLock.lock(); defer { deliveryLock.unlock() }
		return deliveryRevision
	}

	func publish(_ joints: [String: [VNHumanHandPoseObservation.JointName: CGPoint]],
		at timestamp: Date = Date(), revision: Int? = nil) {
		let observationRevision = revision ?? currentDeliveryRevision()
		DispatchQueue.main.async { [weak self] in
			guard let self, self.currentDeliveryRevision() == observationRevision else { return }
			// Hold timers and frame streaks also need observations with identical joints.
			self.observationTimestamp = timestamp
			self.handJoints = joints
		}
	}

	private func distanceSq(_ p1: CGPoint, _ p2: CGPoint) -> CGFloat {
		let dx = p1.x - p2.x
		let dy = p1.y - p2.y
		return dx * dx + dy * dy
	}

	private static let allJoints: [VNHumanHandPoseObservation.JointName] = [
		.wrist, .thumbCMC, .thumbMP, .thumbIP, .thumbTip,
		.indexMCP, .indexPIP, .indexDIP, .indexTip,
		.middleMCP, .middlePIP, .middleDIP, .middleTip,
		.ringMCP, .ringPIP, .ringDIP, .ringTip,
		.littleMCP, .littlePIP, .littleDIP, .littleTip,
	]
}
