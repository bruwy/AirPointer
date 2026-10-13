import CoreGraphics
import Testing
@testable import AirPointer

@Suite("CursorSmoother behavior")
struct CursorSmootherBehaviorTests {

    @Test func firstSamplePassesThrough() {
        let smoother = CursorSmoother(smoothingFactor: 0.25)
        let first = CGPoint(x: 12, y: -4)

        #expect(smoother.smooth(first) == first)
    }

    @Test func appliesExponentialSmoothingFromPreviousOutput() {
        let smoother = CursorSmoother(smoothingFactor: 0.25)

        _ = smoother.smooth(CGPoint(x: 0, y: 0))
        let second = smoother.smooth(CGPoint(x: 8, y: 4))
        let third = smoother.smooth(CGPoint(x: 8, y: 4))

        #expect(abs(second.x - 2.0) < 0.0001)
        #expect(abs(second.y - 1.0) < 0.0001)
        #expect(abs(third.x - 3.5) < 0.0001)
        #expect(abs(third.y - 1.75) < 0.0001)
    }

    @Test func clampsSmoothingFactorToUnitRange() {
        let frozen = CursorSmoother(smoothingFactor: -2)
        _ = frozen.smooth(CGPoint(x: 10, y: 20))

        #expect(frozen.smooth(CGPoint(x: 100, y: 200)) == CGPoint(x: 10, y: 20))

        let immediate = CursorSmoother(smoothingFactor: 3)
        _ = immediate.smooth(CGPoint(x: 10, y: 20))

        #expect(immediate.smooth(CGPoint(x: 100, y: 200)) == CGPoint(x: 100, y: 200))
    }

    @Test func resetDropsPreviousSample() {
        let smoother = CursorSmoother(smoothingFactor: 0.5)
        _ = smoother.smooth(CGPoint(x: 0, y: 0))
        _ = smoother.smooth(CGPoint(x: 10, y: 10))

        smoother.reset()

        let newFirst = CGPoint(x: 50, y: -10)
        #expect(smoother.smooth(newFirst) == newFirst)
    }
}
