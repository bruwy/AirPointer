import CoreGraphics
import Foundation
import Vision

nonisolated enum AirFrameJointName: String, CaseIterable, Codable, Sendable {
	case wrist
	case thumbCMC
	case thumbMP
	case thumbIP
	case thumbTip
	case indexMCP
	case indexPIP
	case indexDIP
	case indexTip
	case middleMCP
	case middlePIP
	case middleDIP
	case middleTip
	case ringMCP
	case ringPIP
	case ringDIP
	case ringTip
	case littleMCP
	case littlePIP
	case littleDIP
	case littleTip

	var visionName: VNHumanHandPoseObservation.JointName {
		switch self {
		case .wrist: return .wrist
		case .thumbCMC: return .thumbCMC
		case .thumbMP: return .thumbMP
		case .thumbIP: return .thumbIP
		case .thumbTip: return .thumbTip
		case .indexMCP: return .indexMCP
		case .indexPIP: return .indexPIP
		case .indexDIP: return .indexDIP
		case .indexTip: return .indexTip
		case .middleMCP: return .middleMCP
		case .middlePIP: return .middlePIP
		case .middleDIP: return .middleDIP
		case .middleTip: return .middleTip
		case .ringMCP: return .ringMCP
		case .ringPIP: return .ringPIP
		case .ringDIP: return .ringDIP
		case .ringTip: return .ringTip
		case .littleMCP: return .littleMCP
		case .littlePIP: return .littlePIP
		case .littleDIP: return .littleDIP
		case .littleTip: return .littleTip
		}
	}

	init?(_ visionName: VNHumanHandPoseObservation.JointName) {
		guard let match = Self.allCases.first(where: { $0.visionName == visionName }) else {
			return nil
		}
		self = match
	}
}

nonisolated struct AirFrameJointFixture: Codable, Equatable, Sendable {
	let name: AirFrameJointName
	let location: CGPoint
}

nonisolated struct AirHandFixture: Codable, Equatable, Sendable {
	let side: AirHandSide
	let joints: [AirFrameJointFixture]

	var airHandSnapshot: AirHandSnapshot {
		let mappedJoints = joints.reduce(
			into: [VNHumanHandPoseObservation.JointName: CGPoint]()
		) { out, joint in
			out[joint.name.visionName] = joint.location
		}

		return AirHandSnapshot(
			side: side,
			joints: mappedJoints,
			wrist: mappedJoints[.wrist]
		)
	}
}

nonisolated struct AirFrameFixture: Codable, Equatable, Sendable {
	let offsetSeconds: TimeInterval
	let hands: [AirHandFixture]

	init(offsetSeconds: TimeInterval, hands: [AirHandFixture]) {
		self.offsetSeconds = offsetSeconds
		self.hands = hands
	}

	init(frame: AirFrame, relativeTo origin: Date) {
		self.offsetSeconds = frame.timestamp.timeIntervalSince(origin)
		self.hands = frame.hands
			.sorted { $0.side.rawValue < $1.side.rawValue }
			.map { hand in
				AirHandFixture(
					side: hand.side,
					joints: hand.joints.compactMap { jointName, location in
						guard let stableName = AirFrameJointName(jointName) else { return nil }
						return AirFrameJointFixture(name: stableName, location: location)
					}
					.sorted { $0.name.rawValue < $1.name.rawValue }
				)
			}
	}

	func airFrame(startingAt startDate: Date) -> AirFrame {
		AirFrame(
			timestamp: startDate.addingTimeInterval(offsetSeconds),
			hands: hands.map(\.airHandSnapshot)
		)
	}
}

nonisolated struct AirFrameRecording: Codable, Equatable, Sendable {
	static let currentSchemaVersion = 1

	let schemaVersion: Int
	let createdAt: Date
	let label: String?
	let frames: [AirFrameFixture]

	init(
		schemaVersion: Int = Self.currentSchemaVersion,
		createdAt: Date = Date(),
		label: String? = nil,
		frames: [AirFrameFixture]
	) {
		self.schemaVersion = schemaVersion
		self.createdAt = createdAt
		self.label = label
		self.frames = frames
	}

	init(frames: [AirFrame], label: String? = nil, createdAt: Date = Date()) {
		let origin = frames.first?.timestamp ?? createdAt
		self.init(
			createdAt: createdAt,
			label: label,
			frames: frames.map { AirFrameFixture(frame: $0, relativeTo: origin) }
		)
	}

	func airFrames(startingAt startDate: Date = Date()) -> [AirFrame] {
		frames.map { $0.airFrame(startingAt: startDate) }
	}
}

final class AirFrameRecorder {
	private var origin: Date?
	private var capturedFrames: [AirFrameFixture] = []

	private(set) var isRecording = false

	func start() {
		origin = nil
		capturedFrames = []
		isRecording = true
	}

	func append(_ frame: AirFrame) {
		guard isRecording else { return }

		let recordingOrigin = origin ?? frame.timestamp
		origin = recordingOrigin
		capturedFrames.append(AirFrameFixture(frame: frame, relativeTo: recordingOrigin))
	}

	func stop(label: String? = nil, createdAt: Date = Date()) -> AirFrameRecording {
		isRecording = false
		let frames = capturedFrames
		capturedFrames = []
		origin = nil
		return AirFrameRecording(createdAt: createdAt, label: label, frames: frames)
	}

	func reset() {
		origin = nil
		capturedFrames = []
		isRecording = false
	}
}

nonisolated struct AirFrameRecordingFileStore {
	let directoryURL: URL
	var encoder = JSONEncoder()
	var decoder = JSONDecoder()
	var fileManager: FileManager = .default

	init(directoryURL: URL = Self.defaultDirectoryURL()) {
		self.directoryURL = directoryURL
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
		encoder.dateEncodingStrategy = .iso8601
		decoder.dateDecodingStrategy = .iso8601
	}

	func write(_ recording: AirFrameRecording, fileName: String? = nil) throws -> URL {
		try fileManager.createDirectory(
			at: directoryURL,
			withIntermediateDirectories: true
		)

		let name = fileName ?? Self.defaultFileName(for: recording)
		let url = directoryURL.appendingPathComponent(name)
		try encoder.encode(recording).write(to: url, options: [.atomic])
		return url
	}

	func read(from url: URL) throws -> AirFrameRecording {
		try decoder.decode(AirFrameRecording.self, from: Data(contentsOf: url))
	}

	static func defaultDirectoryURL() -> URL {
		let appSupport = FileManager.default.urls(
			for: .applicationSupportDirectory,
			in: .userDomainMask
		).first ?? FileManager.default.temporaryDirectory

		return appSupport
			.appendingPathComponent("AirPointer", isDirectory: true)
			.appendingPathComponent("Recordings", isDirectory: true)
	}

	static func defaultFileName(for recording: AirFrameRecording) -> String {
		let stamp = ISO8601DateFormatter()
			.string(from: recording.createdAt)
			.replacingOccurrences(of: ":", with: "-")
		let label = recording.label?
			.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
		let suffix = (label?.isEmpty == false) ? "-\(label!)" : ""
		return "\(stamp)\(suffix)-\(UUID().uuidString).airframes.json"
	}
}

@MainActor
struct AirFrameReplayer {
	let recording: AirFrameRecording

	func frames(startingAt startDate: Date = Date()) -> [AirFrame] {
		recording.airFrames(startingAt: startDate)
	}

	func replay(
		into recognizer: AirGestureRecognizer,
		startingAt startDate: Date = Date()
	) -> [AirGestureEvent] {
		let previousOnGesture = recognizer.onGesture
		let previousOnIntent = recognizer.onIntent
		var events: [AirGestureEvent] = []

		recognizer.onGesture = { event in
			events.append(event)
		}
		recognizer.onIntent = nil

		for frame in frames(startingAt: startDate) {
			recognizer.process(frame: frame)
		}

		recognizer.onGesture = previousOnGesture
		recognizer.onIntent = previousOnIntent

		return events
	}
}
