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
            diagnosticLeftClicks = 0; diagnosticRightClicks = 0; diagnosticMiddleClicks = 0
        }
    }
    @Published private(set) var mouseStatus = "Close fingers to begin"
    @Published private(set) var mouseEvidence = ""
    @Published private(set) var mouseButtonStatus = "Buttons: waiting for left hand"
    @Published private(set) var diagnosticLeftClicks = 0
    @Published private(set) var diagnosticRightClicks = 0
    @Published private(set) var diagnosticMiddleClicks = 0

    static let cursorFeedbackPreferenceKey = "cursorFeedbackEnabled"
    static let gesturesEnabledPreferenceKey = "gesturesEnabled"
    @Published var gesturesEnabled: Bool {
        didSet {
            guard oldValue != gesturesEnabled else { return }
            feedbackDefaults?.set(gesturesEnabled, forKey: Self.gesturesEnabledPreferenceKey)
            resetGestureState()
            resumeGate.requireNeutral()
            updateResumeHint()
        }
    }
    @Published private(set) var gestureResumeHint: String?
    @Published var cursorFeedbackEnabled: Bool {
        didSet {
            guard oldValue != cursorFeedbackEnabled else { return }
            feedbackDefaults?.set(cursorFeedbackEnabled, forKey: Self.cursorFeedbackPreferenceKey)
            cursorFeedback.cancel()
        }
    }
    @Published private(set) var cursorFeedback = CursorFeedbackState()

	@Published var pointerLocation: CGPoint? = nil { // Normalized laser coordinates (0-1)
        didSet { if pointerLocation != nil && heldButtons.pressedButton == nil { cursorFeedback.cancel() } }
    }

	private let tracker: HandTracker
	private let engine: AirCore
	private let gestureRecognizer: AirGestureRecognizer
	private let mouseEngine = LeftMouseEngine()
    private let heldButtons = HeldMouseButtonSession()
    private var diagnosticButton: MouseButton?
    private var resumeGate = GestureResumeGate()
    private var safetyTimer: Timer?
    private var lastFrameReceivedAt: TimeInterval?
	private let dwEngine = DeepworkEngine()
	private let dispatcher: IntentDispatcher
	private let systemActions: SystemActionPerforming
	private let permissionClient: PermissionClient
    private let feedbackDefaults: UserDefaults?
    private let feedbackNow: () -> TimeInterval
    private var cursorWasPaused = false
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
		permissionClient: PermissionClient,
        feedbackDefaults: UserDefaults? = .standard,
        feedbackNow: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
	) {
		let tracker = engine?.tracker ?? HandTracker()
		self.tracker = tracker
		self.engine = engine ?? AirCore(tracker: tracker)
		self.gestureRecognizer = gestureRecognizer
		self.systemActions = systemActions
		self.dispatcher = IntentDispatcher(performer: systemActions)
		self.permissionClient = permissionClient
        self.feedbackDefaults = feedbackDefaults
        self.feedbackNow = feedbackNow
        self.cursorFeedbackEnabled = feedbackDefaults?.object(forKey: Self.cursorFeedbackPreferenceKey) as? Bool ?? true
        self.gesturesEnabled = feedbackDefaults?.object(forKey: Self.gesturesEnabledPreferenceKey) as? Bool ?? true
		self.permissionSnapshot = permissionClient.runtimeSnapshot()
		setup()
	}

	func start() {
		guard !started else { return }
		refreshPermissionSnapshot()
		guard permissionSnapshot.camera.isAuthorized else { return }
        guard releaseHeldButtons() else { startSafetyTimer(); return }
		started = true
        startSafetyTimer()
		engine.start()
	}

	func stop() {
		let wasStarted = started
		started = false
		resetGestureState()
		if wasStarted { engine.stop() }
        if !heldButtons.releasePending { safetyTimer?.invalidate(); safetyTimer = nil }
	}

    deinit { safetyTimer?.invalidate() }

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
        _ = releaseHeldButtons()
        diagnosticButton = nil
        lastFrameReceivedAt = nil
        tracker.invalidatePendingObservations()
        resumeGate.interrupt()
        gestureRecognizer.reset()
        dwEngine.reset()
        mouseEngine.reset()
        cursorFeedback.cancel()
        cursorWasPaused = false
        resetPointer()
        mouseStatus = gesturesEnabled ? "Close fingers to begin" : "Gestures off"
        mouseEvidence = ""
        mouseButtonStatus = gesturesEnabled ? "Buttons: waiting for neutral" : "Buttons: gestures off"
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
		commandStatus = heldButtons.releasePending ? .failed : .idle
	}

	@discardableResult
	private func submit(_ action: SystemAction, label: String) -> Bool {
        guard gesturesEnabled else { return false }
        if diagnosticOnly {
            commandLabel = label
            commandStatus = .diagnostic
            return true // recognition continues, but no performer is called
        }
		commandLabel = label
        guard prepareSubmission() else { return false }
        let revision = actionRevision
		let status: CommandDeliveryStatus = systemActions.perform(action) ? .submitted : .failed
		guard revision == actionRevision, started else { return false }
		if status != .submitted { cancelPendingActions() }
		if commandStatus != status {
			commandLogger.notice("Command \(label, privacy: .public): \(status.rawValue, privacy: .public)")
			commandStatus = status
		}
        if status == .submitted, canShowCursorFeedback {
            switch action {
            case .clickMouse, .shortcut, .mouseButton(_, pressed: true):
                cursorFeedback.recognize(at: feedbackNow())
            default: break // Continuous movement/scroll never pulses.
            }
        }
		return status == .submitted
	}

    private func prepareSubmission() -> Bool {
        guard started, gesturesEnabled else { cancelPendingActions(); return false }
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
        guard accessibility.isTrusted else {
            cancelPendingActions()
            commandStatus = .blockedAccessibility
            return false
        }
        return true
    }

	func getEngine() -> AirCore { engine }
	var handTracker: HandTracker { tracker }

	// MARK: - AirCoreDelegate
	func airCore(_ core: AirCore, didUpdate observedFrame: AirFrame) {
        guard started, permissionSnapshot.camera.isAuthorized else { return }
        let timestamp = observedFrame.timestamp
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
        lastFrameReceivedAt = feedbackNow()
        let revision = actionRevision
        let previousFeedbackCommand = cursorFeedback.commandID
		if isRecordingFrames {
			frameRecorder.append(observedFrame)
		}

		self.handJoints = observedFrame.hands.reduce(into: [:]) { dict, hand in
			dict[hand.side.rawValue] = hand.joints
		}
        guard gesturesEnabled else { return }
        let frame = resumeGate.filter(observedFrame)
        updateResumeHint()
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

            if lState.pinch && heldButtons.pressedButton != nil {
                guard releaseHeldButtons() else { cancelPendingActions(); return }
            }

			let actions = self.dwEngine.process(
				frame: frame, leftState: lState, rightState: rState)
            guard self.execute(actions), revision == actionRevision else { return }
        }
        let mouse = mouseEngine.process(frame: frame,
            reservePinch: activeProfile == .deepwork && (enableScroll || enableScrub),
            sensitivity: mouseSensitivity)
        mouseStatus = resumeGate.waiting.contains(.left) ? "Rearm left hand — relax or open fingers" : mouse.status
        mouseEvidence = mouse.evidence
        mouseButtonStatus = resumeGate.waiting.contains(.left) ? "Buttons: rearm left hand — relax or open fingers" : mouse.buttonStatus
        if activeProfile == .deepwork, r.isPointing,
           let point = frame.hand(for: .right)?.joints[.indexTip], MouseHandPose.valid(point) {
            pointerLocation = point
        } else if pointerLocation != nil { pointerLocation = nil }
        if diagnosticOnly {
            if mouse.desiredButton != diagnosticButton, let button = mouse.desiredButton {
                switch button {
                case .left: diagnosticLeftClicks += 1
                case .right: diagnosticRightClicks += 1
                case .middle: diagnosticMiddleClicks += 1
                }
                commandLabel = button.title
                commandStatus = .diagnostic
            }
            diagnosticButton = mouse.desiredButton
        } else {
            if mouse.desiredButton != nil && heldButtons.pressedButton == nil {
                guard prepareSubmission(), revision == actionRevision else { return }
            }
            let accepted = heldButtons.update(desired: mouse.desiredButton) { action in
                if case .mouseButton(_, pressed: false) = action { return systemActions.perform(action) }
                return submit(action, label: mouse.desiredButton?.title ?? "Release mouse button")
            }
            guard revision == actionRevision else { return }
            guard accepted else {
                cancelPendingActions()
                if started { commandStatus = .failed }
                return
            }
        }
        mouseButtonStatus += diagnosticOnly ? " · diagnostic only" : " · posted: \(heldButtons.pressedButton?.title ?? "none")"
        if let delta = mouse.delta {
            let action = heldButtons.pressedButton.map { SystemAction.dragMouseBy(delta, button: $0) }
                ?? .moveMouseBy(delta)
            guard submit(action, label: "Left hand: trackpad"),
                  revision == actionRevision else { return }
        }
        guard revision == actionRevision else { return }
        if canShowCursorFeedback && !frame.hands.isEmpty {
            if mouse.isPaused && !cursorWasPaused && cursorFeedback.commandID == previousFeedbackCommand {
                cursorFeedback.cancel()
            }
            cursorWasPaused = mouse.isPaused
            cursorFeedback.update(ready: mouse.isReady, at: feedbackNow(), pressedButton: heldButtons.pressedButton)
        } else {
            cursorFeedback.cancel()
            cursorWasPaused = false
        }
	}

    private var canShowCursorFeedback: Bool {
        started && gesturesEnabled && cursorFeedbackEnabled && !diagnosticOnly
            && permissionSnapshot.isReadyForTracking && (pointerLocation == nil || heldButtons.pressedButton != nil)
    }

    // Called by the overlay's lightweight cursor timer, including camera stalls.
    func expireCursorFeedback(at now: TimeInterval? = nil) {
        var feedback = cursorFeedback
        if canShowCursorFeedback { feedback.expire(at: now ?? feedbackNow()) }
        else { feedback.cancel() }
        if feedback != cursorFeedback { cursorFeedback = feedback }
    }

    @discardableResult
    private func releaseHeldButtons() -> Bool {
        let hadButton = heldButtons.pressedButton != nil
        let success = heldButtons.release { systemActions.perform($0) }
        if !success { commandStatus = .failed }
        else if hadButton { cursorFeedback.cancel() }
        return success
    }

    // Button safety is independent of whether the user enables the visual halo.
    func expireTrackingState(at now: TimeInterval? = nil) {
        if heldButtons.pressedButton != nil && permissionClient.runtimeSnapshot() != permissionSnapshot {
            refreshPermissionSnapshot()
        }
        if heldButtons.releasePending { _ = releaseHeldButtons() }
        if let lastFrameReceivedAt {
            let age = (now ?? feedbackNow()) - lastFrameReceivedAt
            if !age.isFinite || age < 0 || age > AppConfig.GestureTuning.maximumFrameGap {
                cancelPendingActions()
            }
        }
        expireCursorFeedback(at: now)
        if !started && !heldButtons.releasePending { safetyTimer?.invalidate(); safetyTimer = nil }
    }

    private func startSafetyTimer() {
        guard safetyTimer == nil else { return }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.expireTrackingState() }
        }
        timer.tolerance = 0.01
        RunLoop.main.add(timer, forMode: .common)
        safetyTimer = timer
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
				guard let self, self.started, self.gesturesEnabled,
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

    private func updateResumeHint() {
        guard gesturesEnabled, !resumeGate.waiting.isEmpty else { gestureResumeHint = nil; return }
        var instructions: [String] = []
        if resumeGate.waiting.contains(.left) { instructions.append("Left: relax or open fingers") }
        if resumeGate.waiting.contains(.right) { instructions.append("Right: open hand") }
        gestureResumeHint = instructions.joined(separator: " · ")
    }
}
