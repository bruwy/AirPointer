import Combine
import AppKit
import SwiftUI
import Vision
import OSLog

@MainActor
final class ContentViewModel: ObservableObject, AirCoreDelegate {

	@Published var handJoints: [String: [VNHumanHandPoseObservation.JointName: CGPoint]] = [:]
	@Published var latestIntent: AirIntent?
	@Published var latestGesture: AirGesture?
	@Published var lastIntentDate: Date?
	@Published var lastGestureDate: Date?
	@Published private(set) var activeProfile: AirProfileKind = .presentation
	@Published var enableNext: Bool = AppConfig.GestureDefaults.enableNext {
        didSet { if oldValue != enableNext { updateAllowedGestures() } }
    }
	@Published var enablePrev: Bool = AppConfig.GestureDefaults.enablePrev {
        didSet { if oldValue != enablePrev { updateAllowedGestures() } }
    }

	@Published var enableMute: Bool = AppConfig.GestureDefaults.enableMute {
        didSet { if oldValue != enableMute { updateAllowedGestures() } }
    }

	// Deepwork Toggles
	@Published var enableScroll: Bool = true {
        didSet { if oldValue != enableScroll { resetContinuousGestures() } }
    }
	@Published var enableScrub: Bool = true {
        didSet { if oldValue != enableScrub { resetContinuousGestures() } }
    }
	@Published var enableVolume: Bool = true {
        didSet { if oldValue != enableVolume { resetContinuousGestures() } }
    }
	@Published var enablePlayPause: Bool = true {
        didSet { if oldValue != enablePlayPause { resetContinuousGestures() } }
    }
	@Published var permissionSnapshot: PermissionRuntimeSnapshot
	@Published var isRecordingFrames: Bool = false
	@Published var lastRecordingURL: URL?
	@Published var recordingErrorMessage: String?
	@Published private(set) var commandLabel = "No command yet"
	@Published private(set) var commandStatus: CommandDeliveryStatus = .idle

	// Gesture States (UI Debug)
	@Published var leftHandState: (pinch: Bool, fist: Bool, dist: CGFloat, isPointing: Bool) = (
		false, false, 0, false
	)

	@Published var rightHandState: (pinch: Bool, fist: Bool, dist: CGFloat, isPointing: Bool) = (
		false, false, 0, false
	)

    @Published var mouseSensitivity: Double = 1.2 {
        didSet { if oldValue != mouseSensitivity { cancelPendingActions() } }
    }
    @Published var diagnosticOnly = false {
        didSet {
            guard oldValue != diagnosticOnly else { return }
            cancelPendingActions()
            if diagnosticOnly && isRecordingFrames {
                _ = frameRecorder.stop(label: "discarded")
                isRecordingFrames = false
            }
            diagnosticLeftClicks = 0; diagnosticRightClicks = 0
        }
    }
    @Published private(set) var mouseStatus = "Close fingers to begin"
    @Published private(set) var mouseEvidence = ""
    @Published private(set) var diagnosticLeftClicks = 0
    @Published private(set) var diagnosticRightClicks = 0

	@Published var pointerLocation: CGPoint? = nil  // Normalized coordinates (0-1)

	private let tracker: HandTracker
	private let engine: AirCore
	private let gestureRecognizer: AirGestureRecognizer
	private let mouseEngine = LeftMouseEngine()
	private let dwEngine = DeepworkEngine()
	private let dispatcher: IntentDispatcher
	private let systemActions: SystemActionPerforming
	private let permissionClient: PermissionClient
	private let frameRecorder = AirFrameRecorder()
	private var started = false
	private var actionRevision = 0
	private var lastProcessedFrameAt: Date?
	private var recordingSaveRevision = 0
	private let commandLogger = Logger(subsystem: "BSC.AirPointer", category: "Commands")

	convenience init(engine: AirCore? = nil) {
		self.init(
			engine: engine,
			gestureRecognizer: AirGestureRecognizer(),
			systemActions: LiveSystemActionPerformer(),
			permissionClient: SystemPermissionClient()
		)
	}

	init(
		engine: AirCore? = nil,
		gestureRecognizer: AirGestureRecognizer,
		systemActions: SystemActionPerforming,
		permissionClient: PermissionClient
	) {
		let tracker = engine?.tracker ?? HandTracker()
		self.tracker = tracker
		self.engine = engine ?? AirCore(tracker: tracker)
		self.gestureRecognizer = gestureRecognizer
		self.systemActions = systemActions
		self.dispatcher = IntentDispatcher(performer: systemActions)
		self.permissionClient = permissionClient
		self.permissionSnapshot = permissionClient.runtimeSnapshot()
		setup()
	}

	func start() {
		guard !started else { return }
		refreshPermissionSnapshot()
		guard permissionSnapshot.camera.isAuthorized else { return }
		started = true
		engine.start()
	}

	func stop() {
		let wasStarted = started
		started = false
		resetGestureState()
		if wasStarted { engine.stop() }
	}

	func refreshPermissionSnapshot() {
		let snapshot = permissionClient.runtimeSnapshot()
		if snapshot != permissionSnapshot { resetGestureState() }
		permissionSnapshot = snapshot
		if !permissionSnapshot.camera.isAuthorized {
			stop()
		}
	}

	func requestCameraPermission() async {
		let camera = await permissionClient.requestCameraAccess()
        cancelPendingActions()
		permissionSnapshot = PermissionRuntimeSnapshot(
			camera: camera,
			accessibility: permissionClient.accessibilityStatus()
		)
		if camera.isAuthorized {
			start()
		}
	}

	func promptForAccessibilityPermission() {
		let accessibility = permissionClient.promptForAccessibilityIfNeeded()
        cancelPendingActions()
		permissionSnapshot = PermissionRuntimeSnapshot(
			camera: permissionClient.cameraStatus(),
			accessibility: accessibility
		)
	}

	func openPrivacySettings() {
		guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") else {
			return
		}
		NSWorkspace.shared.open(url)
	}

	func toggleFrameRecording() {
		isRecordingFrames ? stopFrameRecording() : startFrameRecording()
	}

	func startFrameRecording() {
        guard !diagnosticOnly else { return }
		recordingSaveRevision += 1
		recordingErrorMessage = nil
		lastRecordingURL = nil
		frameRecorder.start()
		isRecordingFrames = true
	}

	func stopFrameRecording() {
		let recording = frameRecorder.stop(label: activeProfile.rawValue)
		isRecordingFrames = false

		guard !recording.frames.isEmpty else { return }

		recordingSaveRevision += 1
		let saveRevision = recordingSaveRevision
		let saveTask = Task.detached(priority: .utility) {
			try AirFrameRecordingFileStore().write(recording)
		}

		Task { @MainActor [weak self] in
			do {
				let url = try await saveTask.value
				guard let self, self.recordingSaveRevision == saveRevision else { return }
				self.lastRecordingURL = url
			} catch {
				guard let self, self.recordingSaveRevision == saveRevision else { return }
				self.recordingErrorMessage = error.localizedDescription
			}
		}
	}

	private func execute(_ actions: [DeepworkEngine.Action]) -> Bool {
		for action in actions {
			let submitted: Bool
			switch action {
			case .scroll(let dx, let dy):
				guard enableScroll else { continue }
				submitted = submit(.scroll(deltaX: dx, deltaY: dy), label: "Scroll")

			case .scrub(let dx):
				guard enableScrub else { continue }
				submitted = submit(.scroll(deltaX: dx, deltaY: 0), label: "Scrub")

			case .playPause:
				guard enablePlayPause else { continue }
				let space = Shortcut(keyCode: 49, modifiers: [])
				submitted = submit(.shortcut(space), label: "Play / Pause")

			case .volume(let delta):
				guard enableVolume else { continue }
				submitted = submit(.volume(delta: delta), label: "Volume")
			}
			// A cancellation/failure invalidates the entire frame's action batch.
			if !submitted { return false }
		}
		return true
	}

	func setProfile(_ kind: AirProfileKind) {
		resetGestureState()
		activeProfile = kind
		dispatcher.setProfile(kind: kind)

		// Enforce Profile Rules
		switch kind {
		case .presentation:
			enableNext = true
			enablePrev = true
			enableMute = false
		case .call:
			enableNext = false
			enablePrev = false
			enableMute = true
		case .deepwork:
			// Deepwork usa gestos contínuos (Scroll, Volume) e não os padrão
			enableNext = false
			enablePrev = false
			enableMute = false

			enableScroll = true
			enableScrub = true
			enableVolume = true
			enablePlayPause = true
		}

		if kind != .deepwork {
			enableScroll = false
			enableScrub = false
			enableVolume = false
			enablePlayPause = false
		}
		updateAllowedGestures()
	}

	func updateAllowedGestures() {
		var allowed = Set<AirGesture>()
		if enableMute { allowed.insert(.pinkyUp) }
		if enableNext { allowed.insert(.pinchDoubleRight) }
		if enablePrev { allowed.insert(.fistRight) }
		if gestureRecognizer.allowedGestures != allowed { cancelPendingActions() }
		gestureRecognizer.allowedGestures = allowed
	}

	func resetContinuousGestures() { cancelPendingActions() }

    private func cancelPendingActions() {
        actionRevision &+= 1
        tracker.invalidatePendingObservations()
        gestureRecognizer.reset()
        dwEngine.reset()
        mouseEngine.reset()
        resetPointer()
        mouseStatus = "Close fingers to begin"
        mouseEvidence = ""
    }

	private func resetGestureState() {
		cancelPendingActions()
		handJoints = [:]
		leftHandState = (false, false, 0, false)
		rightHandState = (false, false, 0, false)
		latestGesture = nil
		latestIntent = nil
		lastGestureDate = nil
		lastIntentDate = nil
		commandLabel = "No command yet"
		commandStatus = .idle
	}

	@discardableResult
	private func submit(_ action: SystemAction, label: String) -> Bool {
        if diagnosticOnly {
            commandLabel = label
            commandStatus = .diagnostic
            return true // recognition continues, but no performer is called
        }
		commandLabel = label
        guard started else { cancelPendingActions(); return false }
        let snapshot = permissionClient.runtimeSnapshot()
        let accessibility = snapshot.accessibility
        if snapshot != permissionSnapshot {
            cancelPendingActions()
            permissionSnapshot = snapshot
            if !snapshot.camera.isAuthorized { stop(); return false }
            if accessibility.isTrusted {
                commandStatus = .permissionChanged
                return false
            }
        }
        let revision = actionRevision
		let status: CommandDeliveryStatus = accessibility.isTrusted
			? (systemActions.perform(action) ? .submitted : .failed)
			: .blockedAccessibility
		guard revision == actionRevision, started else { return false }
		if status != .submitted { cancelPendingActions() }
		if commandStatus != status {
			commandLogger.notice("Command \(label, privacy: .public): \(status.rawValue, privacy: .public)")
			commandStatus = status
		}
		return status == .submitted
	}

	func getEngine() -> AirCore { engine }
	var handTracker: HandTracker { tracker }

	// MARK: - AirCoreDelegate
	func airCore(_ core: AirCore, didUpdate frame: AirFrame) {
        guard started, permissionSnapshot.camera.isAuthorized else { return }
        let timestamp = frame.timestamp
        guard timestamp.timeIntervalSinceReferenceDate.isFinite else { cancelPendingActions(); return }
        if let last = lastProcessedFrameAt {
            let delta = timestamp.timeIntervalSince(last)
            guard delta > 0, delta <= AppConfig.GestureTuning.maximumFrameGap else {
                cancelPendingActions()
                lastProcessedFrameAt = max(last, timestamp)
                return
            }
        }
        lastProcessedFrameAt = timestamp
        let revision = actionRevision
		if isRecordingFrames {
			frameRecorder.append(frame)
		}

		self.handJoints = frame.hands.reduce(into: [:]) { dict, hand in
			dict[hand.side.rawValue] = hand.joints
		}
		self.gestureRecognizer.process(frame: frame)
        guard revision == actionRevision else { cancelPendingActions(); return }

		// Update UI States
		let l = self.gestureRecognizer.getGestureState(for: .left)
		self.leftHandState = (
			pinch: l.isPinching, fist: l.isFist, dist: l.pinchDist, isPointing: l.isPointing
		)

		let r = self.gestureRecognizer.getGestureState(for: .right)
		self.rightHandState = (
			pinch: r.isPinching, fist: r.isFist, dist: r.pinchDist, isPointing: r.isPointing
		)

		// Deepwork Processing
		if self.activeProfile == .deepwork {
			// A relaxed/closed hand belongs to the trackpad even if the thumb
            // touches the index. Share the same arbitration with LeftMouseEngine
            // so scroll and relative movement can never own that pose together.
            let mousePose = frame.hand(for: .left).map { MouseHandPose.analyze($0).pose }
            let lState = (pinch: l.isPinching && mousePose != .closed, fist: l.isFist, dist: l.pinchDist)
			let rState = (pinch: r.isPinching, fist: r.isFist, dist: r.pinchDist)

			let actions = self.dwEngine.process(
				frame: frame, leftState: lState, rightState: rState)
            guard self.execute(actions), revision == actionRevision else { return }
        }
        let mouse = mouseEngine.process(frame: frame,
            reservePinch: activeProfile == .deepwork && (enableScroll || enableScrub),
            sensitivity: mouseSensitivity)
        mouseStatus = mouse.status
        mouseEvidence = mouse.evidence
        pointerLocation = nil
        if let delta = mouse.delta {
            guard submit(.moveMouseBy(delta), label: "Left hand: trackpad"),
                  revision == actionRevision else { return }
        }
        if let right = mouse.rightClick {
            if diagnosticOnly {
                if right { diagnosticRightClicks += 1 } else { diagnosticLeftClicks += 1 }
            }
            submit(.clickMouse(buttonRight: right), label: right ? "Right click" : "Left click")
        }
	}

	var intentLabel: String {
		guard let intent = latestIntent else { return "No intent yet" }
		return intent.displayName
	}

	// MARK: - Private
	private func setup() {
		engine.delegate = self
		setProfile(activeProfile)

		gestureRecognizer.onGesture = { [weak self] event in
				guard let self, self.started,
					self.gestureRecognizer.allowedGestures.contains(event.gesture) else { return }
				self.latestGesture = event.gesture
				self.lastGestureDate = event.timestamp
				self.latestIntent = event.intent
				self.lastIntentDate = event.timestamp
				if let action = self.dispatcher.action(for: event.intent) {
					self.submit(action, label: event.intent.displayName)
				} else {
					self.commandLabel = event.intent.displayName
					self.commandStatus = .unmapped
				}
		}
	}

    private func resetPointer() {
        pointerLocation = nil
    }
}
