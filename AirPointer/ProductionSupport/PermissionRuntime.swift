import Foundation

#if canImport(AVFoundation)
import AVFoundation
#endif

#if os(macOS) && canImport(ApplicationServices)
import ApplicationServices
#endif

nonisolated enum CameraPermissionStatus: Equatable, Sendable {
	case authorized
	case notDetermined
	case denied
	case restricted
	case unsupported
	case unknown(rawValue: Int)

	var isAuthorized: Bool {
		self == .authorized
	}

	var canRequestInApp: Bool {
		self == .notDetermined
	}
}

nonisolated enum AccessibilityPermissionStatus: Equatable, Sendable {
	case trusted
	case notTrusted
	case unsupported

	var isTrusted: Bool {
		self == .trusted
	}
}

nonisolated enum PermissionRequirement: Equatable, Sendable {
	case camera
	case accessibility
}

nonisolated struct PermissionRuntimeSnapshot: Equatable, Sendable {
	let camera: CameraPermissionStatus
	let accessibility: AccessibilityPermissionStatus

	var isReadyForTracking: Bool {
		camera.isAuthorized && accessibility.isTrusted
	}

	var missingRequirements: [PermissionRequirement] {
		var requirements: [PermissionRequirement] = []

		if !camera.isAuthorized {
			requirements.append(.camera)
		}

		if !accessibility.isTrusted {
			requirements.append(.accessibility)
		}

		return requirements
	}
}

nonisolated protocol PermissionClient: Sendable {
	func cameraStatus() -> CameraPermissionStatus
	func accessibilityStatus() -> AccessibilityPermissionStatus
	func requestCameraAccess() async -> CameraPermissionStatus
	func promptForAccessibilityIfNeeded() -> AccessibilityPermissionStatus
}

extension PermissionClient {
	func runtimeSnapshot() -> PermissionRuntimeSnapshot {
		PermissionRuntimeSnapshot(
			camera: cameraStatus(),
			accessibility: accessibilityStatus()
		)
	}
}

nonisolated struct SystemPermissionClient: PermissionClient {
	init() {}

	func cameraStatus() -> CameraPermissionStatus {
		#if canImport(AVFoundation)
		CameraPermissionStatus(AVCaptureDevice.authorizationStatus(for: .video))
		#else
		.unsupported
		#endif
	}

	func accessibilityStatus() -> AccessibilityPermissionStatus {
		#if os(macOS) && canImport(ApplicationServices)
		AXIsProcessTrusted() ? .trusted : .notTrusted
		#else
		.unsupported
		#endif
	}

	func requestCameraAccess() async -> CameraPermissionStatus {
		#if canImport(AVFoundation)
		await withCheckedContinuation { continuation in
			AVCaptureDevice.requestAccess(for: .video) { granted in
				let status: CameraPermissionStatus = granted
					? .authorized
					: CameraPermissionStatus(AVCaptureDevice.authorizationStatus(for: .video))
				continuation.resume(returning: status)
			}
		}
		#else
		.unsupported
		#endif
	}

	func promptForAccessibilityIfNeeded() -> AccessibilityPermissionStatus {
		#if os(macOS) && canImport(ApplicationServices)
		guard !AXIsProcessTrusted() else { return .trusted }

		let options = [
			kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
		] as CFDictionary
		return AXIsProcessTrustedWithOptions(options) ? .trusted : .notTrusted
		#else
		.unsupported
		#endif
	}
}

#if canImport(AVFoundation)
extension CameraPermissionStatus {
	nonisolated init(_ authorizationStatus: AVAuthorizationStatus) {
		switch authorizationStatus {
		case .authorized:
			self = .authorized
		case .notDetermined:
			self = .notDetermined
		case .denied:
			self = .denied
		case .restricted:
			self = .restricted
		@unknown default:
			self = .unknown(rawValue: authorizationStatus.rawValue)
		}
	}
}
#endif

nonisolated struct PermissionOnboardingStep: Equatable, Sendable {
	let requirement: PermissionRequirement
	let title: String
	let message: String
	let primaryActionTitle: String?
	let settingsPathHint: String?
}

nonisolated enum PermissionOnboardingCopy {
	static func steps(for snapshot: PermissionRuntimeSnapshot) -> [PermissionOnboardingStep] {
		var steps: [PermissionOnboardingStep] = []

		if let cameraStep = step(for: snapshot.camera) {
			steps.append(cameraStep)
		}

		if let accessibilityStep = step(for: snapshot.accessibility) {
			steps.append(accessibilityStep)
		}

		return steps
	}

	static func step(for status: CameraPermissionStatus) -> PermissionOnboardingStep? {
		switch status {
		case .authorized:
			return nil
		case .notDetermined:
			return PermissionOnboardingStep(
				requirement: .camera,
				title: "Permitir camera",
				message: "O AirPointer precisa da camera para detectar suas maos e traduzir gestos em comandos.",
				primaryActionTitle: "Permitir camera",
				settingsPathHint: nil
			)
		case .denied:
			return PermissionOnboardingStep(
				requirement: .camera,
				title: "Ativar camera",
				message: "A permissao da camera foi negada. Ative o acesso nos Ajustes do Sistema para usar o rastreamento.",
				primaryActionTitle: "Abrir Ajustes",
				settingsPathHint: "Ajustes do Sistema > Privacidade e Seguranca > Camera"
			)
		case .restricted:
			return PermissionOnboardingStep(
				requirement: .camera,
				title: "Camera restrita",
				message: "Este Mac esta impedindo o acesso a camera por uma restricao do sistema ou de gerenciamento.",
				primaryActionTitle: nil,
				settingsPathHint: "Ajustes do Sistema > Privacidade e Seguranca > Camera"
			)
		case .unsupported:
			return PermissionOnboardingStep(
				requirement: .camera,
				title: "Camera indisponivel",
				message: "Este ambiente nao oferece suporte de camera compativel com o AirPointer.",
				primaryActionTitle: nil,
				settingsPathHint: nil
			)
		case .unknown:
			return PermissionOnboardingStep(
				requirement: .camera,
				title: "Status da camera desconhecido",
				message: "Nao foi possivel confirmar a permissao da camera. Revise o acesso nos Ajustes do Sistema.",
				primaryActionTitle: "Abrir Ajustes",
				settingsPathHint: "Ajustes do Sistema > Privacidade e Seguranca > Camera"
			)
		}
	}

	static func step(for status: AccessibilityPermissionStatus) -> PermissionOnboardingStep? {
		switch status {
		case .trusted:
			return nil
		case .notTrusted:
			return PermissionOnboardingStep(
				requirement: .accessibility,
				title: "Ativar acessibilidade",
				message: "O AirPointer precisa de Acessibilidade para enviar comandos de teclado e rolagem ao aplicativo ativo.",
				primaryActionTitle: "Abrir Ajustes",
				settingsPathHint: "Ajustes do Sistema > Privacidade e Seguranca > Acessibilidade"
			)
		case .unsupported:
			return PermissionOnboardingStep(
				requirement: .accessibility,
				title: "Acessibilidade indisponivel",
				message: "Este ambiente nao oferece a API de Acessibilidade necessaria para controlar o cursor.",
				primaryActionTitle: nil,
				settingsPathHint: nil
			)
		}
	}
}
