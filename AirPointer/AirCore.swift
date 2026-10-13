import Foundation
import Combine
import Vision
import AVFoundation

enum AirHandSide: String, Codable, Sendable {
	case left, right
}

struct AirHandSnapshot {
	let side: AirHandSide
	let joints: [VNHumanHandPoseObservation.JointName: CGPoint]
	let wrist: CGPoint?
}

struct AirFrame {
	let timestamp: Date
	let hands: [AirHandSnapshot]

	func hand(for side: AirHandSide) -> AirHandSnapshot? {
		hands.first(where: { $0.side == side })
	}
}

@MainActor
protocol AirCoreDelegate: AnyObject {
	func airCore(_ core: AirCore, didUpdate frame: AirFrame)
}

@MainActor
final class AirCore: ObservableObject {
	weak var delegate: AirCoreDelegate?
	@Published private(set) var latestFrame: AirFrame?

	let session: AVCaptureSession
	let tracker: HandTracker
	private var cancellables = Set<AnyCancellable>()

	init(tracker: HandTracker) {
		self.tracker = tracker
		self.session = tracker.session
		
		tracker.$handJoints
			.sink { [weak self] joints in
				self?.processFrame(joints: joints)
			}
			.store(in: &cancellables)
	}

	func start() { tracker.start() }
	func stop() { tracker.stop() }

	private func processFrame(joints: [String: [VNHumanHandPoseObservation.JointName: CGPoint]]) {
		let receivedAt = Date()
		let observedAt = tracker.observationTimestamp ?? receivedAt
		let age = receivedAt.timeIntervalSince(observedAt)
		let isFresh = age.isFinite && age >= 0 && age <= AppConfig.GestureTuning.maximumFrameGap
		var snapshots: [AirHandSnapshot] = []
		
		for (sideLabel, points) in joints where isFresh {
			guard let side = AirHandSide(rawValue: sideLabel) else { continue }
			
			let snapshot = AirHandSnapshot(
				side: side,
				joints: points,
				wrist: points[.wrist]
			)
			snapshots.append(snapshot)
		}
		
		// Stale observations become a fresh empty frame, immediately cancelling
		// held gestures instead of making old joints appear newly observed.
		let frame = AirFrame(timestamp: isFresh ? observedAt : receivedAt, hands: snapshots)
		self.latestFrame = frame
		self.delegate?.airCore(self, didUpdate: frame)
	}
}
