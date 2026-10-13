import CoreGraphics
import Foundation
import Testing
import Vision
@testable import AirPointer

@MainActor
@Suite("DeepworkEngine behavior")
struct DeepworkEngineBehaviorTests {

    @Test func leftPinchUsesOffsetAndKeepsScrubbingWhileStationary() throws {
        let engine = DeepworkEngine()
        let base = Date(timeIntervalSinceReferenceDate: 1_000)
        let leftPinching = (pinch: true, fist: false, dist: CGFloat(0.08))
        let rightIdle = (pinch: false, fist: false, dist: CGFloat(1))

        let start = engine.process(
            frame: frame(at: base, leftWrist: CGPoint(x: 0.5, y: 0.5)),
            leftState: leftPinching,
            rightState: rightIdle
        )
        #expect(start.isEmpty)

        let withinDeadzone = engine.process(
            frame: frame(at: base.addingTimeInterval(0.1), leftWrist: CGPoint(x: 0.51, y: 0.5)),
            leftState: leftPinching,
            rightState: rightIdle
        )
        #expect(withinDeadzone.isEmpty)

        let firstScrollActions = engine.process(
            frame: frame(at: base.addingTimeInterval(0.2), leftWrist: CGPoint(x: 0.7, y: 0.5)),
            leftState: leftPinching,
            rightState: rightIdle
        )
        let firstScroll = try #require(onlyScrub(in: firstScrollActions))
        #expect(firstScroll.dx > 0)
        #expect(firstScroll.dy == 0)

        let cruiseActions = engine.process(
            frame: frame(at: base.addingTimeInterval(0.3), leftWrist: CGPoint(x: 0.7, y: 0.5)),
            leftState: leftPinching,
            rightState: rightIdle
        )
        let cruise = try #require(onlyScrub(in: cruiseActions))
        #expect(abs(cruise.dx - firstScroll.dx) <= 1)
        #expect(cruise.dy == firstScroll.dy)
    }

    @Test func releasingLeftPinchClearsDragState() throws {
        let engine = DeepworkEngine()
        let base = Date(timeIntervalSinceReferenceDate: 2_000)
        let leftPinching = (pinch: true, fist: false, dist: CGFloat(0.08))
        let leftReleased = (pinch: false, fist: false, dist: CGFloat(1))
        let rightIdle = (pinch: false, fist: false, dist: CGFloat(1))

        _ = engine.process(
            frame: frame(at: base, leftWrist: CGPoint(x: 0.5, y: 0.5)),
            leftState: leftPinching,
            rightState: rightIdle
        )
        _ = engine.process(
            frame: frame(at: base.addingTimeInterval(0.1), leftWrist: CGPoint(x: 0.7, y: 0.5)),
            leftState: leftPinching,
            rightState: rightIdle
        )
        let moving = engine.process(
            frame: frame(at: base.addingTimeInterval(0.2), leftWrist: CGPoint(x: 0.9, y: 0.5)),
            leftState: leftPinching,
            rightState: rightIdle
        )
        _ = try #require(onlyScrub(in: moving))

        let released = engine.process(
            frame: frame(at: base.addingTimeInterval(0.3), leftWrist: CGPoint(x: 0.9, y: 0.5)),
            leftState: leftReleased,
            rightState: rightIdle
        )
        #expect(released.isEmpty)

        let reanchored = engine.process(
            frame: frame(at: base.addingTimeInterval(0.4), leftWrist: CGPoint(x: 0.1, y: 0.1)),
            leftState: leftPinching,
            rightState: rightIdle
        )
        #expect(reanchored.isEmpty)
    }

    @Test func rightFistRequiresHoldAndTriggersOncePerHold() {
        let engine = DeepworkEngine()
        let base = Date(timeIntervalSinceReferenceDate: 3_000)
        let leftIdle = (pinch: false, fist: false, dist: CGFloat(1))
        let rightFist = (pinch: false, fist: true, dist: CGFloat(0.04))
        let rightOpen = (pinch: false, fist: false, dist: CGFloat(1))

        #expect(engine.process(
            frame: frame(at: base, rightWrist: CGPoint(x: 0.6, y: 0.5)),
            leftState: leftIdle,
            rightState: rightFist
        ).isEmpty)

        for i in 1...9 {
            #expect(engine.process(
                frame: frame(at: base.addingTimeInterval(Double(i) * 0.1), rightWrist: CGPoint(x: 0.6, y: 0.5)),
                leftState: leftIdle, rightState: rightFist
            ).isEmpty)
        }

        #expect(engine.process(
            frame: frame(at: base.addingTimeInterval(0.99), rightWrist: CGPoint(x: 0.6, y: 0.5)),
            leftState: leftIdle,
            rightState: rightFist
        ).isEmpty)

        #expect(containsPlayPause(engine.process(
            frame: frame(at: base.addingTimeInterval(1.0), rightWrist: CGPoint(x: 0.6, y: 0.5)),
            leftState: leftIdle,
            rightState: rightFist
        )))

        #expect(engine.process(
            frame: frame(at: base.addingTimeInterval(1.2), rightWrist: CGPoint(x: 0.6, y: 0.5)),
            leftState: leftIdle,
            rightState: rightFist
        ).isEmpty)

        #expect(engine.process(
            frame: frame(at: base.addingTimeInterval(1.3), rightWrist: CGPoint(x: 0.6, y: 0.5)),
            leftState: leftIdle,
            rightState: rightOpen
        ).isEmpty)

        #expect(engine.process(
            frame: frame(at: base.addingTimeInterval(1.31), rightWrist: CGPoint(x: 0.6, y: 0.5)),
            leftState: leftIdle,
            rightState: rightFist
        ).isEmpty)

        for i in 1...9 {
            #expect(engine.process(
                frame: frame(at: base.addingTimeInterval(1.31 + Double(i) * 0.1), rightWrist: CGPoint(x: 0.6, y: 0.5)),
                leftState: leftIdle, rightState: rightFist
            ).isEmpty)
        }

        #expect(containsPlayPause(engine.process(
            frame: frame(at: base.addingTimeInterval(2.32), rightWrist: CGPoint(x: 0.6, y: 0.5)),
            leftState: leftIdle,
            rightState: rightFist
        )))
    }

    @Test func rightFistStateIsIgnoredWithoutRightHandFrame() {
        let engine = DeepworkEngine()
        let base = Date(timeIntervalSinceReferenceDate: 4_000)
        let leftIdle = (pinch: false, fist: false, dist: CGFloat(1))
        let rightFist = (pinch: false, fist: true, dist: CGFloat(0.04))

        #expect(engine.process(
            frame: frame(at: base),
            leftState: leftIdle,
            rightState: rightFist
        ).isEmpty)

        #expect(engine.process(
            frame: frame(at: base.addingTimeInterval(2.0)),
            leftState: leftIdle,
            rightState: rightFist
        ).isEmpty)
    }
}

private func frame(
    at timestamp: Date,
    leftWrist: CGPoint? = nil,
    rightWrist: CGPoint? = nil
) -> AirFrame {
    var hands: [AirHandSnapshot] = []

    if let leftWrist {
        hands.append(handSnapshot(side: .left, wrist: leftWrist))
    }

    if let rightWrist {
        hands.append(handSnapshot(side: .right, wrist: rightWrist))
    }

    return AirFrame(timestamp: timestamp, hands: hands)
}

private func handSnapshot(side: AirHandSide, wrist: CGPoint) -> AirHandSnapshot {
    let joints = syntheticJoints(for: .pinch).mapValues {
        CGPoint(x: $0.x * 0.1 + wrist.x, y: $0.y * 0.1 + wrist.y)
    }
    return AirHandSnapshot(side: side, joints: joints, wrist: wrist)
}

private func onlyScrub(in actions: [DeepworkEngine.Action]) -> (dx: Int32, dy: Int32)? {
    guard actions.count == 1 else { return nil }

    guard case let .scrub(dx) = actions[0] else {
        return nil
    }

    return (dx, 0)
}

private func containsPlayPause(_ actions: [DeepworkEngine.Action]) -> Bool {
    actions.contains { action in
        guard case .playPause = action else {
            return false
        }

        return true
    }
}
