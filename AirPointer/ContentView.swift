import SwiftUI
import Vision
import AVFoundation
import AppKit

struct ContentView: View {
	@ObservedObject var viewModel: ContentViewModel
	
	@State private var showSkeletonOverlay = AppConfig.showSkeletonOverlay
	@State private var showHUD: Bool = AppConfig.showHUD
	@State private var showGestureMenu: Bool = false

	var body: some View {
		GeometryReader { geo in
			ZStack(alignment: .topLeading) {
				
				// --- CAMADA 1: VÍDEO E OVERLAY ---
				ZStack {
					// Assume que CameraView pega o engine ou session internamente
					CameraView(engine: viewModel.getEngine())
						.frame(width: geo.size.width, height: geo.size.height)

					if showSkeletonOverlay {
						// Passamos os joints direto do ViewModel
						HandSkeletonOverlayView(
							hands: viewModel.handJoints,
							mirrorHorizontally: true
						)
						.frame(width: geo.size.width, height: geo.size.height)
						.allowsHitTesting(false)
					}
				}
				.ignoresSafeArea()

				if !viewModel.permissionSnapshot.isReadyForTracking {
					PermissionStatusPanel(
						snapshot: viewModel.permissionSnapshot,
						requestCamera: {
							Task { await viewModel.requestCameraPermission() }
						},
						promptAccessibility: {
							viewModel.promptForAccessibilityPermission()
						},
						openSettings: {
							viewModel.openPrivacySettings()
						},
						refresh: {
							viewModel.refreshPermissionSnapshot()
							viewModel.start()
						}
					)
					.padding(.top, 96)
					.padding(.horizontal, 20)
					.frame(maxWidth: 520, alignment: .topLeading)
				}
				
				// --- CAMADA 2: UI ---
				VStack {
					controlBar
						.padding(.top, 40)
						.padding(.horizontal)
					
					Spacer()
					
					if showHUD {
						HStack {
							// NOTA: Certifique-se de que 'handTracker' no ContentViewModel NÃO é private
							IntentHUD(
								lastIntent: viewModel.latestIntent,
								lastIntentDate: viewModel.lastIntentDate,
								lastGesture: viewModel.latestGesture,
								lastGestureDate: viewModel.lastGestureDate,
								activeProfile: viewModel.activeProfile,
								commandLabel: viewModel.commandLabel,
								commandStatus: viewModel.commandStatus,
								handJoints: viewModel.handJoints,
								leftState: viewModel.leftHandState,
								rightState: viewModel.rightHandState,
								isRunning: viewModel.handTracker.session.isRunning
							)
							Spacer()
						}
						.padding(.bottom, 40)
						.padding(.leading, 20)
					}
					
					if showGestureMenu {
						FloatingGestureMenu(
							enableNext: $viewModel.enableNext,
							enablePrev: $viewModel.enablePrev,
							enableMute: $viewModel.enableMute,
							enableScroll: $viewModel.enableScroll,
							enableScrub: $viewModel.enableScrub,
							enableVolume: $viewModel.enableVolume,
							enablePlayPause: $viewModel.enablePlayPause,
                            sensitivity: $viewModel.mouseSensitivity,
                            diagnosticOnly: $viewModel.diagnosticOnly,
                            mouseStatus: viewModel.mouseStatus,
                            mouseEvidence: viewModel.mouseEvidence,
                            diagnosticCounts: "Left: \(viewModel.diagnosticLeftClicks)  Right: \(viewModel.diagnosticRightClicks)",
							activeProfile: viewModel.activeProfile
						)
						.frame(width: 340)
						.padding(.bottom, 40)
						.padding(.trailing, 20)
						.transition(.move(edge: .trailing).combined(with: .opacity))
						.alignmentGuide(.trailing) { d in d[.trailing] }
						.alignmentGuide(.bottom) { d in d[.bottom] }
					}
				}
			}
		}
		.onAppear {
			viewModel.refreshPermissionSnapshot()
			viewModel.updateAllowedGestures()
			viewModel.start()
		}
		.onDisappear { viewModel.stop() }
		.onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
			viewModel.stop()
		}
		.onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
			viewModel.refreshPermissionSnapshot()
			viewModel.start()
		}
	}

	private var controlBar: some View {
		HStack(spacing: 12) {
            Text("V4 Trackpad").font(.caption.bold())
			Picker("Profile", selection: Binding(get: { viewModel.activeProfile }, set: { viewModel.setProfile($0) })) {
				ForEach(AirProfileKind.allCases, id: \.self) { profile in
					Text(profile.title).tag(profile)
				}
			}
			.pickerStyle(.segmented)
			.frame(maxWidth: .infinity)

			Button(action: { showSkeletonOverlay.toggle() }) {
				Image(systemName: showSkeletonOverlay ? "hand.raised.slash.fill" : "hand.raised")
					.font(.system(size: 18, weight: .semibold))
					.frame(width: 44, height: 32)
			}
			.buttonStyle(.borderedProminent)
			.tint(.black.opacity(0.6))
			.accessibilityLabel("Hand skeleton overlay")
			.accessibilityValue(showSkeletonOverlay ? "On" : "Off")
			.help(showSkeletonOverlay ? "Hide hand skeleton" : "Show hand skeleton")

			Button(action: { showHUD.toggle() }) {
				Image(systemName: showHUD ? "gauge.with.dots.needle.bottom.50percent" : "gauge")
					.font(.system(size: 18, weight: .semibold))
					.frame(width: 44, height: 32)
			}
			.buttonStyle(.borderedProminent)
			.tint(.black.opacity(0.6))
			.accessibilityLabel("Tracking status panel")
			.accessibilityValue(showHUD ? "On" : "Off")
			.help(showHUD ? "Hide tracking status" : "Show tracking status")
			
			Button(action: { withAnimation { showGestureMenu.toggle() } }) {
				Image(systemName: "slider.horizontal.3")
					.font(.system(size: 18, weight: .semibold))
					.frame(width: 44, height: 32)
			}
			.buttonStyle(.borderedProminent)
			.tint(.black.opacity(0.6))
			.accessibilityLabel("Gesture settings")
			.accessibilityValue(showGestureMenu ? "Open" : "Closed")
			.help(showGestureMenu ? "Hide gesture settings" : "Show gesture settings")

			Button(action: { viewModel.toggleFrameRecording() }) {
				Image(systemName: viewModel.isRecordingFrames ? "stop.circle.fill" : "record.circle")
					.font(.system(size: 18, weight: .semibold))
					.frame(width: 44, height: 32)
			}
			.buttonStyle(.borderedProminent)
			.tint(viewModel.isRecordingFrames ? .red : .black.opacity(0.6))
			.accessibilityLabel("Gesture frame recording")
			.accessibilityValue(viewModel.isRecordingFrames ? "Recording" : "Stopped")
			.help(viewModel.isRecordingFrames ? "Stop frame recording" : "Start frame recording")
		}
		.padding(10)
		.background(.regularMaterial)
		.clipShape(Capsule())
		.shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
		.overlay(
			Capsule()
				.stroke(.white.opacity(0.1), lineWidth: 1)
		)
	}
}

private struct PermissionStatusPanel: View {
	let snapshot: PermissionRuntimeSnapshot
	let requestCamera: () -> Void
	let promptAccessibility: () -> Void
	let openSettings: () -> Void
	let refresh: () -> Void

	private var steps: [PermissionOnboardingStep] {
		PermissionOnboardingCopy.steps(for: snapshot)
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 14) {
			HStack(alignment: .center) {
				Label("Setup required", systemImage: "hand.raised.fill")
					.font(.system(size: 13, weight: .bold))
					.foregroundStyle(.white)

				Spacer()

				Button(action: refresh) {
					Image(systemName: "arrow.clockwise")
						.frame(width: 28, height: 24)
				}
				.buttonStyle(.borderless)
				.foregroundStyle(.white.opacity(0.8))
				.accessibilityLabel("Refresh permissions")
				.help("Check permissions again")
			}

			ForEach(steps, id: \.requirement) { step in
				permissionRow(step)
			}
		}
		.padding(16)
		.background(.regularMaterial)
		.clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
		.overlay(
			RoundedRectangle(cornerRadius: 14, style: .continuous)
				.stroke(.white.opacity(0.14), lineWidth: 1)
		)
		.shadow(color: .black.opacity(0.18), radius: 18, x: 0, y: 8)
		.environment(\.colorScheme, .dark)
	}

	private func permissionRow(_ step: PermissionOnboardingStep) -> some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack(alignment: .firstTextBaseline) {
				Text(step.title)
					.font(.system(size: 13, weight: .semibold))
					.foregroundStyle(.white)
				Spacer()
				actionButton(for: step)
			}

			Text(step.message)
				.font(.system(size: 12))
				.foregroundStyle(.white.opacity(0.72))
				.fixedSize(horizontal: false, vertical: true)

			if let hint = step.settingsPathHint {
				Text(hint)
					.font(.system(size: 11, design: .monospaced))
					.foregroundStyle(.white.opacity(0.48))
					.fixedSize(horizontal: false, vertical: true)
			}
		}
		.padding(.top, 2)
	}

	@ViewBuilder
	private func actionButton(for step: PermissionOnboardingStep) -> some View {
		if let title = step.primaryActionTitle {
			Button(title) {
				switch step.requirement {
				case .camera:
					snapshot.camera.canRequestInApp ? requestCamera() : openSettings()
				case .accessibility:
					promptAccessibility()
				}
			}
			.buttonStyle(.borderedProminent)
			.controlSize(.small)
		}
	}
}

// MARK: - HUD Revisado
private struct IntentHUD: View {
	let lastIntent: AirIntent?
	let lastIntentDate: Date?
	let lastGesture: AirGesture?
	let lastGestureDate: Date?
	let activeProfile: AirProfileKind
	let commandLabel: String
	let commandStatus: CommandDeliveryStatus
	let handJoints: [String: [VNHumanHandPoseObservation.JointName: CGPoint]]
	
	// Updated States direct from ViewModel
	let leftState: (pinch: Bool, fist: Bool, dist: CGFloat, isPointing: Bool)
	let rightState: (pinch: Bool, fist: Bool, dist: CGFloat, isPointing: Bool)
	let isRunning: Bool

	var body: some View {
		VStack(alignment: .leading, spacing: 12) {
			HStack {
				Text("Air Pointer")
					.font(.system(size: 14, weight: .bold, design: .rounded))
					.foregroundStyle(.secondary)
				Spacer()
				Text(isRunning ? "LIVE" : "STOPPED")
					.font(.system(size: 10, weight: .bold))
					.padding(.horizontal, 4)
					.padding(.vertical, 2)
					.background(isRunning ? Color.green : Color.red)
					.foregroundStyle(.white)
					.clipShape(Capsule())
					.accessibilityLabel(isRunning ? "Tracking active" : "Tracking stopped")
			}

			Divider().background(Color.white.opacity(0.2))

			Group {
				row(label: "Profile", value: activeProfile.title)
				row(label: "Gesture", value: gestureText)
				row(label: "Command", value: commandLabel)
				row(label: "Delivery", value: commandStatus.rawValue)
				row(label: "Action", value: intentText)
				if let recency = recencyText {
					Text(recency)
						.font(.system(size: 10, design: .monospaced))
						.foregroundColor(.gray)
						.padding(.top, -4)
				}
			}
			
			Divider().background(Color.white.opacity(0.2))
			
			HStack(spacing: 16) {
				statusIndicator(
					side: "L",
					present: hasLeft,
					pinch: leftState.pinch,
					fist: leftState.fist,
					dist: leftState.dist,
					isPointing: leftState.isPointing)
				Divider().frame(height: 30).background(Color.white.opacity(0.2))
				statusIndicator(
					side: "R",
					present: hasRight,
					pinch: rightState.pinch,
					fist: rightState.fist,
					dist: rightState.dist,
					isPointing: rightState.isPointing)
			}
			.padding(.top, 2)
		}

		.padding(16)
		.background(.regularMaterial)
		.cornerRadius(20)
		.overlay(
			RoundedRectangle(cornerRadius: 20)
				.stroke(.white.opacity(0.1), lineWidth: 1)
		)
		.shadow(color: .black.opacity(0.2), radius: 15, x: 0, y: 8)
		.frame(width: 260)
		.accessibilityElement(children: .combine)
		.environment(\.colorScheme, .dark)
	}
	
	private func row(label: String, value: String) -> some View {
		HStack {
			Text(label).foregroundColor(.white.opacity(0.6))
			Spacer()
			Text(value).foregroundColor(.white).bold()
		}
		.font(.system(size: 12))
	}
	
	private func statusIndicator(
		side: String, present: Bool, pinch: Bool, fist: Bool, dist: CGFloat, isPointing: Bool
	) -> some View {
		{
			let dVal = dist * 1000
			let color: Color = {
				if pinch { return .green }
				else if dVal < 70 { return .yellow }
				else { return .white }
			}()
			let pointingColor: Color = isPointing ? .cyan : .white.opacity(0.4)

			return VStack(alignment: .leading, spacing: 3) {
				Text(side == "L" ? "LEFT HAND" : "RIGHT HAND")
					.font(.system(size: 9, weight: .bold))
					.foregroundColor(present ? .white.opacity(0.8) : .white.opacity(0.3))
				
				if present {
					HStack(alignment: .firstTextBaseline, spacing: 4) {
						Text(pinch ? "PINCH" : String(format: "%.0f", dVal))
							.font(.system(size: 14, weight: .bold, design: .monospaced))
							.foregroundColor(color)
						
						if !pinch {
							Text("dist")
								.font(.system(size: 9))
								.foregroundColor(.gray)
						}
					}
					
					Text(fist ? "FIST: ON" : "Fist: --")
						.font(.system(size: 10))
						.foregroundColor(fist ? .orange : .white.opacity(0.4))
					Text(isPointing ? "POINT: ON" : "Point: --")
						.font(.system(size: 10))
						.foregroundColor(pointingColor)
				} else {
					Text("--")
						.font(.system(size: 14, design: .monospaced))
						.foregroundColor(.white.opacity(0.2))
					Text("No Signal")
						.font(.system(size: 9))
						.foregroundColor(.white.opacity(0.2))
				}
			}
			.frame(minWidth: 80, alignment: .leading)
		}()
	}

	// Helpers
	private var hasLeft: Bool { handJoints["left"] != nil }
	private var hasRight: Bool { handJoints["right"] != nil }
	
	private var gestureText: String { lastGesture?.displayName ?? "Ready" }
	private var intentText: String { lastIntent?.displayName ?? "Ready" }
	
	private var recencyText: String? {
		let date = lastGestureDate ?? lastIntentDate
		guard let date = date else { return nil }
		let interval = Date().timeIntervalSince(date)
		if interval < 1.0 { return "Just now" }
		return String(format: "%.1fs ago", interval)
	}
}

private struct FloatingGestureMenu: View {
	@Binding var enableNext: Bool
	@Binding var enablePrev: Bool
	@Binding var enableMute: Bool
	
	@Binding var enableScroll: Bool
	@Binding var enableScrub: Bool
	@Binding var enableVolume: Bool
	@Binding var enablePlayPause: Bool
    @Binding var sensitivity: Double
    @Binding var diagnosticOnly: Bool
    var mouseStatus: String
    var mouseEvidence: String
    var diagnosticCounts: String
	
	var activeProfile: AirProfileKind

	var body: some View {
		ScrollView {
		VStack(alignment: .leading, spacing: 12) {
			Text(activeProfile == .deepwork ? "Deepwork" : "Gestures")
				.font(.system(size: 12, weight: .black))
				.textCase(.uppercase)
				.foregroundColor(.white.opacity(0.9))

            Label("V4 Trackpad • Left hand • All modes", systemImage: "cursorarrow")
                .font(.caption.bold())
            Text("Close/relax the four fingers and move your wrist like a trackpad. Open the hand to reposition without moving the cursor; close to resume. For a click, raise index (left) or index + middle (right), hold briefly, then close the fingers. The cursor parks during clicks. Opening the hand cancels the click. Thumb may rest naturally.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Sensitivity: \(sensitivity, specifier: "%.1f")×")
                .font(.caption)
            Slider(value: $sensitivity, in: 0.5...3, step: 0.1)
                .accessibilityLabel("Trackpad sensitivity")
            Text(mouseStatus).font(.caption.bold())
            Toggle("Diagnostic only — no commands", isOn: $diagnosticOnly)
                .toggleStyle(.switch)
            if diagnosticOnly {
                Text(mouseEvidence).font(.caption.monospaced())
                Text(diagnosticCounts).font(.caption.monospaced())
                Text("Live text only. No images or landmarks saved. I/M/R/L = index, middle, ring, little.")
                    .font(.caption).foregroundStyle(.secondary)
            }

			if activeProfile == .deepwork {
				Toggle(isOn: $enableScroll) {
					Label("Scroll (L pinch + hold offset)", systemImage: "arrow.up.and.down.circle")
				}
				.toggleStyle(.switch)
				.tint(.purple)
				.help("Pinch the left hand, move up or down, then hold to keep scrolling. Return to the pinch origin to stop; release or remove the hand to cancel.")

				Toggle(isOn: $enableScrub) {
					Label("Scrub (L pinch + hold offset)", systemImage: "hand.draw.fill")
				}
				.toggleStyle(.switch)
				.tint(.purple)
				.help("Horizontal scrolling continues while the pinching left hand stays offset. Return to the origin to stop; release to cancel.")
				
				Toggle(isOn: $enableVolume) {
					Label("Volume (unavailable)", systemImage: "speaker.wave.3.fill")
				}
				.toggleStyle(.switch)
				.tint(.purple)
				.disabled(true)
				.help("Volume gestures are unavailable in this version.")
				
				Toggle(isOn: $enablePlayPause) {
					Label("Play/Pause (R fist)", systemImage: "play.pause.circle.fill")
				}
				.toggleStyle(.switch)
				.tint(.purple)
				Text("Pinch with the other fingers open to scroll; the cursor parks. Release and close the fingers to resume the trackpad. Thumb contact in a closed hand stays neutral.")
					.font(.caption)
					.foregroundStyle(.secondary)
				
			} else {
				Toggle(isOn: $enableNext) {
					Label("Next Slide (R dbl pinch)", systemImage: "chevron.right.circle")
				}
				.toggleStyle(.switch)
				.tint(.green)

				Toggle(isOn: $enablePrev) {
					Label("Prev Slide (R fist)", systemImage: "chevron.left.circle")
				}
				.toggleStyle(.switch)
				.tint(.green)
				.help("Open the right hand for 0.15 s to arm; close and hold for 0.25 s to go back once. Reopen to rearm. The left hand controls the mouse.")
				if activeProfile == .presentation {
					Text("Open R to arm; close briefly to go back once. Reopen to rearm. Left hand controls the mouse.")
						.font(.caption)
						.foregroundStyle(.secondary)
				}

					Toggle(isOn: $enableMute) {
						Label("Zoom mute (R pinky up)", systemImage: "mic.slash.circle")
					}
				.toggleStyle(.switch)
				.tint(.blue)
			}
		}
		.padding(16)
        }
        .frame(maxHeight: 440)
		.background(.thickMaterial)
		.cornerRadius(20)
		.overlay(
			RoundedRectangle(cornerRadius: 20)
				.stroke(.white.opacity(0.1), lineWidth: 1)
		)
		.shadow(color: .black.opacity(0.3), radius: 20, x: 0, y: 10)
		.environment(\.colorScheme, .dark)
	}
}
