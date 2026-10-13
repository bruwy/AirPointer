import CoreGraphics
import Foundation
import Vision

/// Consome `AirFrame` snapshots e emite gestos de alto nível mapeados para `AirIntent`.
/// Slides usam double pinch direito e punho direito; pinky up controla mute.
@MainActor
final class AirGestureRecognizer {
	var onGesture: ((AirGestureEvent) -> Void)?
	var onIntent: ((AirIntent) -> Void)?
	var allowedGestures: Set<AirGesture> = Set(AirGesture.allCases) {
		didSet {
			if oldValue != allowedGestures { reset() }
		}
	}

	private struct MotionSample {
		let time: TimeInterval
		let point: CGPoint
	}

	// MARK: - Internal Physics State
	private struct HandPhysicsState {
		var pinchDistEMA: CGFloat = 0
		var isPinching: Bool = false
		var pinchOnStreak: Int = 0
		var pinchOffStreak: Int = 0

		var isFist: Bool = false
		var fistOnStreak: Int = 0
		var fistOffStreak: Int = 0

		var isPointing: Bool = false
		var pointOnStreak: Int = 0
		var pointOffStreak: Int = 0
	}

	private var physicsState: [AirHandSide: HandPhysicsState] = [
		.left: HandPhysicsState(),
		.right: HandPhysicsState(),
	]

	private var motionHistory: [AirHandSide: [MotionSample]] = [:]
	private var pinkyUpStart: [AirHandSide: Date] = [:]
	private var cooldowns: [AirIntent: Date] = [:]
	private var previousPinchState: [AirHandSide: Bool] = [.left: false, .right: false]
	private var pinchTapCount: [AirHandSide: Int] = [.left: 0, .right: 0]
	private var lastPinchAt: [AirHandSide: Date] = [:]
	private var pinchStartAt: [AirHandSide: Date] = [:]
	private var latchedPinkyHands = Set<AirHandSide>()
	private var presentationFistArmed = false
	private var presentationFistStart: Date?
	private var presentationFistReleaseStart: Date?
	private var lastFrameAt: Date?

	func reset() {
		physicsState = [.left: HandPhysicsState(), .right: HandPhysicsState()]
		motionHistory = [:]
		pinkyUpStart = [:]
		latchedPinkyHands = []
		resetPresentationFist()
		cooldowns = [:]
		for side in [AirHandSide.left, .right] { resetDoublePinch(for: side) }
		lastFrameAt = nil
	}

	func process(frame: AirFrame) {
		let now = frame.timestamp
		guard now.timeIntervalSinceReferenceDate.isFinite else { reset(); return }
		if let last = lastFrameAt, now <= last { reset(); return }
		if let last = lastFrameAt,
			now.timeIntervalSince(last) > AppConfig.GestureTuning.maximumFrameGap {
			reset()
		}
		lastFrameAt = now
		var seenSides = Set<AirHandSide>()

		for hand in frame.hands {
			seenSides.insert(hand.side)

			// 1. Update Physics (Pinch/Fist Detection)
			updatePhysics(for: hand)
			let state = physicsState[hand.side] ?? HandPhysicsState()

			// 2. Motion Tracking
			if let anchor = anchorPoint(for: hand) {
				registerMotion(anchor: anchor, for: hand.side, at: now)
			}

			// 3. High-Level Gesture Recognition

			// Double Pinch
			let rawFist = HandPoseMetrics.fistMetric(from: hand.joints)
			if hand.side == .right, allowedGestures.contains(.pinchDoubleRight),
				!state.isFist, let rawFist, rawFist >= AppConfig.GestureTuning.fistThresholdOn,
				HandPoseMetrics.pinchDistanceNormalized(from: hand.joints) != nil {
				detectDoublePinch(side: hand.side, isPinching: state.isPinching, now: now)
			} else {
				resetDoublePinch(for: hand.side)
			}
			if hand.side == .right {
				detectPresentationFist(hand: hand, state: state, now: now)
			}

			// Pinky Up (Mute)
			// Evita disparo enquanto está em pinch/fist ou muito próximo de pinch.
			let isNearPinch = state.pinchDistEMA > 0
				&& state.pinchDistEMA < AppConfig.GestureTuning.minPinchDistanceForPinky
			if state.isPinching
				|| isNearPinch
				|| state.isFist
			{
				resetPinkyUp(for: hand.side)
				latchedPinkyHands.remove(hand.side)
				continue
			}

			detectPinkyUp(hand: hand, now: now)
		}

		for side in [AirHandSide.left, AirHandSide.right] where !seenSides.contains(side) {
			physicsState[side] = HandPhysicsState()
			motionHistory[side] = []
			resetPinkyUp(for: side)
			latchedPinkyHands.remove(side)
			resetDoublePinch(for: side)
			if side == .right { resetPresentationFist() }
		}
	}

	// A complete open hand arms the command. Unknown/lost observations never
	// rearm it, so an occluded held fist cannot become a second slide command.
	private func resetPresentationFist() {
		presentationFistArmed = false
		presentationFistStart = nil
		presentationFistReleaseStart = nil
	}

	private func detectPresentationFist(hand: AirHandSnapshot, state: HandPhysicsState, now: Date) {
		guard allowedGestures.contains(.fistRight),
			let wrist = hand.wrist, wrist.x.isFinite, wrist.y.isFinite,
			let fist = HandPoseMetrics.fistMetric(from: hand.joints),
			let pinch = HandPoseMetrics.pinchDistanceNormalized(from: hand.joints) else {
			resetPresentationFist()
			return
		}
		let open = fist > AppConfig.GestureTuning.fistThresholdOff
			&& pinch > AppConfig.GestureTuning.pinchThresholdOff && !state.isFist
		if open {
			presentationFistStart = nil
			if presentationFistReleaseStart == nil { presentationFistReleaseStart = now }
			if let start = presentationFistReleaseStart,
				now.timeIntervalSince(start) >= AppConfig.GestureTuning.presentationFistRearmHold {
				presentationFistArmed = true
			}
			return
		}
		presentationFistReleaseStart = nil
		guard presentationFistArmed, state.isFist,
			fist < AppConfig.GestureTuning.fistThresholdOn else {
			presentationFistStart = nil
			return
		}
		if presentationFistStart == nil { presentationFistStart = now }
		if let start = presentationFistStart,
			now.timeIntervalSince(start) >= AppConfig.GestureTuning.presentationFistHold {
			resetPresentationFist()
			resetDoublePinch(for: .right)
			emit(gesture: .fistRight, hand: .right, at: now)
		}
	}

	// MARK: - Pinky Up Detection
	private func detectPinkyUp(hand: AirHandSnapshot, now: Date) {
		guard hand.side == .right, allowedGestures.contains(.pinkyUp), isPinkyUpPose(joints: hand.joints) else {
			resetPinkyUp(for: hand.side)
			latchedPinkyHands.remove(hand.side)
			return
		}
		guard !latchedPinkyHands.contains(hand.side) else { return }

		let motion = recentMotion(for: hand.side, window: AppConfig.GestureTuning.pinkyUpHold)
		if motion < AppConfig.GestureTuning.pinkyUpMotionTolerance {
			if pinkyUpStart[hand.side] == nil { pinkyUpStart[hand.side] = now }
			if let start = pinkyUpStart[hand.side],
				now.timeIntervalSince(start) >= AppConfig.GestureTuning.pinkyUpHold,
				allow(
					intent: .toggleMute, now: now,
					cooldown: AppConfig.GestureTuning.pinkyUpCooldown)
			{
				emit(gesture: .pinkyUp, hand: hand.side, at: now)
				latchedPinkyHands.insert(hand.side)
				pinkyUpStart[hand.side] = nil
			}
		} else {
			resetPinkyUp(for: hand.side)
		}
	}

	// MARK: - Helpers
	private func anchorPoint(for hand: AirHandSnapshot) -> CGPoint? {
		if let wrist = hand.wrist { return wrist }
		if let i = hand.joints[.indexMCP], let l = hand.joints[.littleMCP] {
			return CGPoint(x: (i.x + l.x) / 2, y: (i.y + l.y) / 2)
		}
		return nil
	}

	private func registerMotion(anchor: CGPoint, for side: AirHandSide, at date: Date) {
		var samples = motionHistory[side] ?? []
		samples.append(MotionSample(time: date.timeIntervalSinceReferenceDate, point: anchor))

		let cutoff = date.timeIntervalSinceReferenceDate - AppConfig.GestureTuning.pinkyUpHold
		while let first = samples.first, first.time < cutoff { samples.removeFirst() }

		motionHistory[side] = samples
	}

	private func allow(intent: AirIntent, now: Date, cooldown: TimeInterval) -> Bool {
		if let last = cooldowns[intent], now.timeIntervalSince(last) < cooldown { return false }
		cooldowns[intent] = now
		return true
	}

	private func recentMotion(for side: AirHandSide, window: TimeInterval) -> CGFloat {
		guard let samples = motionHistory[side], samples.count >= 2,
			let last = samples.last
		else { return .greatestFiniteMagnitude }

		let cutoff = last.time - window
		let relevant = samples.filter { $0.time >= cutoff }
		guard let first = relevant.first else { return .greatestFiniteMagnitude }

		let dx = relevant.map { abs($0.point.x - first.point.x) }.max() ?? 0
		let dy = relevant.map { abs($0.point.y - first.point.y) }.max() ?? 0
		return max(dx, dy)
	}

	private func isPinkyUpPose(
		joints: [VNHumanHandPoseObservation.JointName: CGPoint]
	) -> Bool {
		HandPoseMetrics.isPinkyUpPose(
			joints: joints,
			pinkyExtendedMin: AppConfig.GestureTuning.pinkyExtendedMin,
			othersMax: AppConfig.GestureTuning.pinkyOthersMax,
			thumbMax: AppConfig.GestureTuning.pinkyThumbMax,
			verticalLiftMin: AppConfig.GestureTuning.pinkyVerticalLiftMin
		)
	}

	private func resetPinkyUp(for side: AirHandSide) {
		pinkyUpStart[side] = nil
	}

	private func resetDoublePinch(for side: AirHandSide) {
		previousPinchState[side] = false
		pinchTapCount[side] = 0
		lastPinchAt[side] = nil
		pinchStartAt[side] = nil
	}

	public func getGestureState(for side: AirHandSide) -> (
		isPinching: Bool, isFist: Bool, isPointing: Bool, pinchDist: CGFloat
	) {
		guard let state = physicsState[side] else { return (false, false, false, 0) }
		return (state.isPinching, state.isFist, state.isPointing, state.pinchDistEMA)
	}

	private func detectDoublePinch(side: AirHandSide, isPinching: Bool, now: Date) {
		let wasPinching = previousPinchState[side] ?? false

		if isPinching && !wasPinching {
			pinchStartAt[side] = now
		} else if !isPinching && wasPinching {
			let pinchStart = pinchStartAt[side] ?? now
			pinchStartAt[side] = nil
			let holdDuration = now.timeIntervalSince(pinchStart)

			guard holdDuration >= AppConfig.GestureTuning.pinchTapMinHold,
				holdDuration <= AppConfig.GestureTuning.pinchTapMaxHold
			else {
				pinchTapCount[side] = 0
				lastPinchAt[side] = nil
				previousPinchState[side] = isPinching
				return
			}

			let last = lastPinchAt[side] ?? .distantPast
			let elapsed = now.timeIntervalSince(last)
			guard elapsed >= AppConfig.GestureTuning.pinchTapMinSeparation else {
				previousPinchState[side] = isPinching
				return
			}

			if elapsed <= AppConfig.GestureTuning.pinchTapWindow {
				pinchTapCount[side, default: 0] += 1
			} else {
				pinchTapCount[side] = 1
			}
			lastPinchAt[side] = now

			if pinchTapCount[side, default: 0] >= AppConfig.GestureTuning.pinchTapCount {
				if allow(
					intent: .nextSlide,
					now: now,
					cooldown: AppConfig.GestureTuning.pinchCooldown) {
					emit(gesture: .pinchDoubleRight, hand: side, at: now)
				}
				// A completed double tap is consumed even during cooldown.
				pinchTapCount[side] = 0
				lastPinchAt[side] = nil
			}
		}
		previousPinchState[side] = isPinching
	}

	// MARK: - Physics Calculation
	private func updatePhysics(for hand: AirHandSnapshot) {
		var state = physicsState[hand.side] ?? HandPhysicsState()
		let joints = hand.joints

		// --- FIST Metric ---
		if let fistVal = HandPoseMetrics.fistMetric(from: joints) {
			if fistVal < AppConfig.GestureTuning.fistThresholdOn {
				state.fistOnStreak += 1
				state.fistOffStreak = 0
				if !state.isFist && state.fistOnStreak >= AppConfig.GestureTuning.fistFramesOn {
					state.isFist = true
					state.fistOnStreak = 0
				}
			} else if fistVal > AppConfig.GestureTuning.fistThresholdOff {
				state.fistOffStreak += 1
				state.fistOnStreak = 0
				if state.isFist && state.fistOffStreak >= AppConfig.GestureTuning.fistFramesOff {
					state.isFist = false
					state.fistOffStreak = 0
				}
			} else {
				state.fistOnStreak = 0
				state.fistOffStreak = 0
			}
		} else {
			// Unknown observations cancel a held command immediately. Hysteresis
			// applies only to complete poses, never to missing joint evidence.
			state.isFist = false
			state.fistOnStreak = 0
			state.fistOffStreak = 0
		}

		// --- PINCH Metric ---
		if let dNorm = HandPoseMetrics.pinchDistanceNormalized(from: joints) {
			// EMA Smoothing
			let alpha = AppConfig.GestureTuning.smoothingAlpha
			if state.pinchDistEMA == 0 { state.pinchDistEMA = dNorm }  // Initialize
			state.pinchDistEMA = (state.pinchDistEMA * (1 - alpha)) + (dNorm * alpha)

			// Hysteresis
			if !state.isPinching {
				if state.pinchDistEMA < AppConfig.GestureTuning.pinchThresholdOn {
					state.pinchOnStreak += 1
					if state.pinchOnStreak >= AppConfig.GestureTuning.pinchFramesOn {
						state.isPinching = true
						state.pinchOnStreak = 0
					}
				} else {
					state.pinchOnStreak = 0
				}
			} else {
				if state.pinchDistEMA > AppConfig.GestureTuning.pinchThresholdOff {
					state.pinchOffStreak += 1
					if state.pinchOffStreak >= AppConfig.GestureTuning.pinchFramesOff {
						state.isPinching = false
						state.pinchOffStreak = 0
					}
				} else {
					state.pinchOffStreak = 0
				}
			}
		} else {
			state.pinchOnStreak = 0
			if state.isPinching {
				state.pinchOffStreak += 1
				if state.pinchOffStreak >= AppConfig.GestureTuning.pinchFramesOff {
					state.isPinching = false
					state.pinchOffStreak = 0
				}
			}
		}

		// --- POINTING Metric ---
		// Heuristic: Index Extended while middle/ring are curled.
		if let dIndex = HandPoseMetrics.extensionRatio(for: .indexTip, from: joints),
			let dMiddle = HandPoseMetrics.extensionRatio(for: .middleTip, from: joints),
			let dRing = HandPoseMetrics.extensionRatio(for: .ringTip, from: joints)
		{
			let indexExtended = dIndex > AppConfig.GestureTuning.pointingIndexMin
			let middleCurled = dMiddle < AppConfig.GestureTuning.pointingMiddleMax
			let ringCurled = dRing < AppConfig.GestureTuning.pointingRingMax
			let pointingCandidate = indexExtended && middleCurled && ringCurled
				&& !state.isPinching
				&& !state.isFist

			if pointingCandidate {
				state.pointOnStreak += 1
				state.pointOffStreak = 0
				if !state.isPointing && state.pointOnStreak >= AppConfig.GestureTuning.pointingFramesOn
				{
					state.isPointing = true
					state.pointOnStreak = 0
				}
			} else {
				state.pointOffStreak += 1
				state.pointOnStreak = 0
				if state.isPointing
					&& state.pointOffStreak >= AppConfig.GestureTuning.pointingFramesOff
				{
					state.isPointing = false
					state.pointOffStreak = 0
				}
			}
		} else {
			state.pointOnStreak = 0
			state.pointOffStreak += 1
			if state.isPointing
				&& state.pointOffStreak >= AppConfig.GestureTuning.pointingFramesOff
			{
				state.isPointing = false
				state.pointOffStreak = 0
			}
		}

		physicsState[hand.side] = state
	}

	private func emit(gesture: AirGesture, hand: AirHandSide?, at date: Date) {
		guard allowedGestures.contains(gesture) else { return }
		let event = AirGestureEvent(
			gesture: gesture, intent: gesture.intent, hand: hand, timestamp: date)
		onGesture?(event)
		onIntent?(event.intent)
	}
}
