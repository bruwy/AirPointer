import Testing
@testable import AirPointer

struct PermissionRuntimeTests {
	@Test func snapshotReadinessRequiresCameraAndAccessibility() {
		let ready = PermissionRuntimeSnapshot(
			camera: .authorized,
			accessibility: .trusted
		)
		#expect(ready.isReadyForTracking)
		#expect(ready.missingRequirements.isEmpty)

		let missingCamera = PermissionRuntimeSnapshot(
			camera: .denied,
			accessibility: .trusted
		)
		#expect(!missingCamera.isReadyForTracking)
		#expect(missingCamera.missingRequirements == [.camera])

		let missingBoth = PermissionRuntimeSnapshot(
			camera: .notDetermined,
			accessibility: .notTrusted
		)
		#expect(!missingBoth.isReadyForTracking)
		#expect(missingBoth.missingRequirements == [.camera, .accessibility])
	}

	@Test func onboardingStepsOnlyDescribeMissingPermissions() {
		let snapshot = PermissionRuntimeSnapshot(
			camera: .authorized,
			accessibility: .notTrusted
		)

		let steps = PermissionOnboardingCopy.steps(for: snapshot)

		#expect(steps.map(\.requirement) == [.accessibility])
		#expect(steps.first?.primaryActionTitle == "Abrir Ajustes")
		#expect(steps.first?.settingsPathHint?.contains("Acessibilidade") == true)
	}

	@Test func cameraCopySeparatesInitialRequestFromSettingsRecovery() {
		let requestStep = PermissionOnboardingCopy.step(for: CameraPermissionStatus.notDetermined)
		#expect(requestStep?.requirement == .camera)
		#expect(requestStep?.primaryActionTitle == "Permitir camera")
		#expect(requestStep?.settingsPathHint == nil)

		let deniedStep = PermissionOnboardingCopy.step(for: CameraPermissionStatus.denied)
		#expect(deniedStep?.requirement == .camera)
		#expect(deniedStep?.primaryActionTitle == "Abrir Ajustes")
		#expect(deniedStep?.settingsPathHint?.contains("Camera") == true)
	}

	@Test func permissionClientCanBeFakedForRuntimeDecisions() async {
		let client = FakePermissionClient(
			camera: .denied,
			accessibility: .trusted,
			requestedCamera: .authorized,
			promptedAccessibility: .trusted
		)

		#expect(client.runtimeSnapshot() == PermissionRuntimeSnapshot(
			camera: .denied,
			accessibility: .trusted
		))
		#expect(await client.requestCameraAccess() == .authorized)
		#expect(client.promptForAccessibilityIfNeeded() == .trusted)
	}
}

private struct FakePermissionClient: PermissionClient {
	let camera: CameraPermissionStatus
	let accessibility: AccessibilityPermissionStatus
	let requestedCamera: CameraPermissionStatus
	let promptedAccessibility: AccessibilityPermissionStatus

	func cameraStatus() -> CameraPermissionStatus {
		camera
	}

	func accessibilityStatus() -> AccessibilityPermissionStatus {
		accessibility
	}

	func requestCameraAccess() async -> CameraPermissionStatus {
		requestedCamera
	}

	func promptForAccessibilityIfNeeded() -> AccessibilityPermissionStatus {
		promptedAccessibility
	}
}
