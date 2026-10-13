import CoreGraphics
import Foundation
import Testing
import Vision
@testable import AirPointer

@MainActor
@Suite("Gesture command regressions", .serialized)
struct GestureCommandRegressionTests {
    @Test func heldPinkyFiresOnceUntilPoseIsReleased() {
        let recognizer = AirGestureRecognizer()
        var events: [AirGestureEvent] = []
        recognizer.onGesture = { events.append($0) }
        feedPinky(into: recognizer, from: 0, through: 3)
        #expect(events.map(\.gesture) == [.pinkyUp])
        recognizer.process(frame: frame(at: time(3.1), side: .right, pose: .open))
        feedPinky(into: recognizer, from: 3.2, through: 4)
        #expect(events.map(\.gesture) == [.pinkyUp, .pinkyUp])
    }

    @Test func missingThumbCannotCompletePinchTap() {
        let recognizer = AirGestureRecognizer()
        var events: [AirGestureEvent] = []
        recognizer.onGesture = { events.append($0) }
        recognizer.process(frame: frame(at: time(0), side: .right, pose: .pinch))
        recognizer.process(frame: frame(at: time(0.05), side: .right, pose: .pinch))
        var incomplete = syntheticJoints(for: .pinch)
        incomplete[.thumbTip] = nil
        recognizer.process(frame: jointsFrame(incomplete, at: 0.12))
        for (offset, pose) in [(0.17, SyntheticHandPose.open), (0.3, .pinch),
                               (0.35, .pinch), (0.4, .pinch), (0.45, .pinch), (0.55, .open)] {
            recognizer.process(frame: frame(at: time(offset), side: .right, pose: pose))
        }
        #expect(events.isEmpty)
    }

    @Test func missingThumbCannotAuthorizePinkyPose() {
        let recognizer = AirGestureRecognizer()
        var events: [AirGestureEvent] = []
        recognizer.onGesture = { events.append($0) }
        var joints = pinkyJoints()
        joints[.thumbTip] = nil
        for i in 0...30 {
            recognizer.process(frame: jointsFrame(joints, at: Double(i) * 0.05))
        }
        #expect(events.isEmpty)
    }

    @Test func rightPinchDoesNotActAsFist() {
        let engine = DeepworkEngine()
        for i in 0...60 {
            let offset = Double(i) * 0.05
            let actions = engine.process(
                frame: frame(at: time(offset), side: .right, pose: .pinch),
                leftState: (false, false, 1), rightState: (true, false, 0.04)
            )
            #expect(actions.isEmpty)
        }
    }

    @Test func unknownPinchDistanceDoesNotActAsFist() {
        let engine = DeepworkEngine()
        for i in 0...60 {
            let offset = Double(i) * 0.05
            let actions = engine.process(
                frame: jointsFrame([.wrist: CGPoint(x: 0.6, y: 0.5)], at: offset),
                leftState: (false, false, 1), rightState: (false, false, 0)
            )
            #expect(actions.isEmpty)
        }
    }
}

func time(_ offset: TimeInterval) -> Date {
    Date(timeIntervalSinceReferenceDate: 10_000 + offset)
}

func jointsFrame(
    _ joints: [VNHumanHandPoseObservation.JointName: CGPoint],
    at offset: TimeInterval,
    side: AirHandSide = .right
) -> AirFrame {
    AirFrame(timestamp: time(offset), hands: [
        AirHandSnapshot(side: side, joints: joints, wrist: joints[.wrist])
    ])
}

func pinkyJoints() -> [VNHumanHandPoseObservation.JointName: CGPoint] {
    [.wrist: CGPoint(x: 0.5, y: 0.3), .middleMCP: CGPoint(x: 0.5, y: 0.5),
     .indexMCP: CGPoint(x: 0.45, y: 0.48), .littleMCP: CGPoint(x: 0.55, y: 0.48),
     .indexTip: CGPoint(x: 0.48, y: 0.46), .middleTip: CGPoint(x: 0.5, y: 0.46),
     .ringTip: CGPoint(x: 0.52, y: 0.46), .littleTip: CGPoint(x: 0.58, y: 0.62),
     .littlePIP: CGPoint(x: 0.56, y: 0.52), .thumbTip: CGPoint(x: 0.36, y: 0.38)]
}

func feedPinky(into recognizer: AirGestureRecognizer, from start: Double, through end: Double) {
    for i in 0...Int(((end - start) / 0.05).rounded()) {
        recognizer.process(frame: jointsFrame(pinkyJoints(), at: start + Double(i) * 0.05))
    }
}
