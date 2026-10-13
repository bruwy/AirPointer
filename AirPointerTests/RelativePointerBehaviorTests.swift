import CoreGraphics
import Foundation
import Testing
@testable import AirPointer

@MainActor
@Suite("Relative pointer physics")
struct RelativePointerBehaviorTests {
    @Test func firstObservationAndStationaryHandEmitNoMovement() {
        var engine = RelativePointerEngine()
        for i in 0..<90 {
            #expect(engine.process(wrist: CGPoint(x: 0.3, y: 0.4), scale: 0.15,
                                   at: time(Double(i) / 30), sensitivity: 1.2) == nil)
        }
    }

    @Test func fasterSameDistanceTravelsFartherAndSensitivityScalesIt() {
        let slow = trajectory(frames: 90, fps: 30, travel: 0.08, sensitivity: 1)
        let fast = trajectory(frames: 10, fps: 30, travel: 0.08, sensitivity: 1)
        let sensitive = trajectory(frames: 90, fps: 30, travel: 0.08, sensitivity: 2)
        #expect(abs(slow) > 30)
        #expect(abs(fast) > abs(slow) * 2)
        #expect(abs(sensitive - 2 * slow) < 0.1)
        #expect(fast < 0 && slow < 0) // mirrored camera X
    }

    @Test func thirtyAndSixtyFPSHaveSimilarTravel() {
        let a = trajectory(frames: 30, fps: 30, travel: 0.06, sensitivity: 1)
        let b = trajectory(frames: 60, fps: 60, travel: 0.06, sensitivity: 1)
        #expect(abs(a - b) / abs(a) < 0.12)
    }

    @Test func palmNormalizationHandlesCameraDistance() {
        let near = trajectory(frames: 30, fps: 30, travel: 0.06, sensitivity: 1, scale: 0.15)
        let far = trajectory(frames: 30, fps: 30, travel: 0.03, sensitivity: 1, scale: 0.075)
        #expect(abs(near - far) < 0.1)
    }

    @Test func smallJitterDoesNotDriftButSlowTravelAccumulates() {
        var engine = RelativePointerEngine()
        for i in 0..<120 {
            let jitter: CGFloat = i.isMultiple(of: 2) ? 0.0003 : -0.0003
            #expect(engine.process(wrist: CGPoint(x: 0.4 + jitter, y: 0.3 - jitter), scale: 0.15,
                                   at: time(Double(i) / 30), sensitivity: 1) == nil)
        }
        #expect(abs(trajectory(frames: 120, fps: 30, travel: 0.015, sensitivity: 1)) > 10)
    }

    @Test func resetGapJumpAndScaleChangeDoNotCatchUp() {
        for reason in 0..<4 {
            var engine = RelativePointerEngine()
            _ = engine.process(wrist: CGPoint(x: 0.3, y: 0.3), scale: 0.15, at: time(0), sensitivity: 1)
            #expect(engine.process(wrist: CGPoint(x: 0.32, y: 0.3), scale: 0.15, at: time(0.04), sensitivity: 1) != nil)
            switch reason {
            case 0: engine.reset()
            case 1: _ = engine.process(wrist: CGPoint(x: 0.7, y: 0.3), scale: 0.15, at: time(0.08), sensitivity: 1)
            case 2: _ = engine.process(wrist: CGPoint(x: 0.7, y: 0.3), scale: 0.15, at: time(1), sensitivity: 1)
            default: _ = engine.process(wrist: CGPoint(x: 0.32, y: 0.3), scale: 0.05, at: time(0.08), sensitivity: 1)
            }
            #expect(engine.process(wrist: CGPoint(x: 0.7, y: 0.3), scale: 0.15, at: time(1.1), sensitivity: 1) == nil)
            #expect(engine.process(wrist: CGPoint(x: 0.7, y: 0.3), scale: 0.15, at: time(1.14), sensitivity: 1) == nil)
        }
    }

    @Test func relativeEventsAreBoundedAndRejectNonfiniteInput() {
        var engine = RelativePointerEngine()
        _ = engine.process(wrist: CGPoint(x: 0.3, y: 0.3), scale: 0.15, at: time(0), sensitivity: 3)
        let movement = engine.process(wrist: CGPoint(x: 0.39, y: 0.35), scale: 0.15, at: time(0.04), sensitivity: 3)
        #expect(movement != nil)
        if let movement { #expect(hypot(movement.dx, movement.dy) <= 96.001) }
        #expect(engine.process(wrist: CGPoint(x: CGFloat.nan, y: 0.3), scale: 0.15, at: time(0.08), sensitivity: 1) == nil)
    }

    @Test func relativeCoordinatesUseCurrentCursorAndCrossAdjacentDisplays() {
        let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: -1920, y: -300, width: 1920, height: 1080)]
        let delta = CGVector(dx: -30, dy: -20)
        #expect(MouseController.relativePoint(current: CGPoint(x: 10, y: 100), delta: delta, screens: screens) == CGPoint(x: -20, y: 80))
        #expect(MouseController.relativePoint(current: CGPoint(x: 500, y: 400), delta: delta, screens: screens) == CGPoint(x: 470, y: 380))
        #expect(MouseController.relativePoint(current: CGPoint(x: -1910, y: -290), delta: delta, screens: screens) == CGPoint(x: -1920, y: -300))
        #expect(MouseController.relativePoint(current: .zero, delta: delta, screens: []) == nil)
    }
}

private func trajectory(frames: Int, fps: Double, travel: CGFloat, sensitivity: Double, scale: CGFloat = 0.15) -> CGFloat {
    var engine = RelativePointerEngine()
    var total: CGFloat = 0
    for i in 0...frames {
        let x = 0.3 + CGFloat(i) / CGFloat(frames) * travel
        total += engine.process(wrist: CGPoint(x: x, y: 0.3), scale: scale,
                                at: time(Double(i) / fps), sensitivity: sensitivity)?.dx ?? 0
    }
    return total
}
