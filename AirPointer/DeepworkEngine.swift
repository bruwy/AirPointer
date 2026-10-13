import CoreGraphics
import Foundation
import Vision

@MainActor
final class DeepworkEngine {

    enum Action {
        case scroll(dx: Int32, dy: Int32)
        case scrub(dx: Int32)
        case volume(delta: Float)  // +1 or -1 roughly
        case playPause
    }

    private var dragStartLocation: CGPoint?
    private var fractionalX: CGFloat = 0
    private var fractionalY: CGFloat = 0

    // Tuning
    private let playPauseCooldown: TimeInterval = 0.6
    private let fistHoldDuration: TimeInterval = 1.0  // Require closed hand for this long

    private var lastPlayPauseAt: Date?
    private var fistStartAt: Date?
    private var didTriggerPlayPauseDuringHold: Bool = false
    private var lastFrameAt: Date?

    func process(
        frame: AirFrame,
        leftState: (pinch: Bool, fist: Bool, dist: CGFloat),
        rightState: (pinch: Bool, fist: Bool, dist: CGFloat)
    ) -> [Action] {
        guard frame.timestamp.timeIntervalSinceReferenceDate.isFinite else { reset(); return [] }
        if let last = lastFrameAt, frame.timestamp <= last { reset(); return [] }
        if let last = lastFrameAt,
           frame.timestamp.timeIntervalSince(last) > AppConfig.GestureTuning.maximumFrameGap {
            reset()
        }
        let elapsed = min(lastFrameAt.map { frame.timestamp.timeIntervalSince($0) } ?? 0,
                          AppConfig.ScrollTuning.maximumEventInterval)
        lastFrameAt = frame.timestamp
        var actions: [Action] = []

        // 1. Right Hand: Play / Pause (Fist Toggle)
        let rightPresent = frame.hand(for: .right) != nil
        let fistActive = rightPresent && rightState.fist

        if fistActive {
            if fistStartAt == nil { fistStartAt = frame.timestamp }

            if let start = fistStartAt,
               !didTriggerPlayPauseDuringHold,
               frame.timestamp.timeIntervalSince(start) >= fistHoldDuration,
               canTriggerPlayPause(at: frame.timestamp) {
                actions.append(.playPause)
                lastPlayPauseAt = frame.timestamp
                didTriggerPlayPauseDuringHold = true
            }
        } else {
            fistStartAt = nil
            didTriggerPlayPauseDuringHold = false
        }

        // Rate control: a held offset from the pinch origin means a held speed.
        // Each event needs a fresh complete pose; there is no autonomous timer.
        guard leftState.pinch, !leftState.fist,
              let hand = frame.hand(for: .left), let wrist = hand.wrist,
              wrist.x.isFinite, wrist.y.isFinite,
              (0...1).contains(wrist.x), (0...1).contains(wrist.y),
              let pinch = HandPoseMetrics.pinchDistanceNormalized(from: hand.joints),
              pinch < AppConfig.GestureTuning.pinchThresholdOff,
              let fist = HandPoseMetrics.fistMetric(from: hand.joints),
              fist >= AppConfig.GestureTuning.fistThresholdOff else {
            resetDrag()
            return actions
        }
        guard let origin = dragStartLocation else {
            dragStartLocation = wrist
            return actions
        }
        let dx = pixelDelta(velocity: velocity(for: wrist.x - origin.x),
                            elapsed: elapsed, fraction: &fractionalX)
        let dy = pixelDelta(velocity: velocity(for: wrist.y - origin.y),
                            elapsed: elapsed, fraction: &fractionalY)
        appendMovement(dx: dx, dy: dy, to: &actions)
        return actions
    }

    func reset() {
        resetDrag()
        fistStartAt = nil
        didTriggerPlayPauseDuringHold = false
        lastPlayPauseAt = nil
        lastFrameAt = nil
    }

    private func appendMovement(dx: Int32, dy: Int32, to actions: inout [Action]) {
        if dy != 0 { actions.append(.scroll(dx: 0, dy: dy)) }
        if dx != 0 { actions.append(.scrub(dx: dx)) }
    }

    private func resetDrag() {
        dragStartLocation = nil
        fractionalX = 0
        fractionalY = 0
    }

    private func velocity(for offset: CGFloat) -> CGFloat {
        let neutral = AppConfig.ScrollTuning.neutralDisplacement
        guard abs(offset) > neutral else { return 0 }
        let travel = AppConfig.ScrollTuning.fullSpeedDisplacement - neutral
        let fraction = min((abs(offset) - neutral) / travel, 1)
        return (offset < 0 ? -1 : 1) * fraction * AppConfig.ScrollTuning.maximumPixelsPerSecond
    }

    private func pixelDelta(velocity: CGFloat, elapsed: TimeInterval, fraction: inout CGFloat) -> Int32 {
        guard velocity != 0 else { fraction = 0; return 0 }
        if fraction * velocity < 0 { fraction = 0 }
        let budget = fraction + velocity * CGFloat(elapsed)
        let pixels = Int32(budget.rounded(.towardZero))
        fraction = budget - CGFloat(pixels)
        return pixels
    }

    private func canTriggerPlayPause(at date: Date) -> Bool {
        guard let last = lastPlayPauseAt else { return true }
        return date.timeIntervalSince(last) > playPauseCooldown
    }
}
