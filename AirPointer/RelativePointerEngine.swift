import CoreGraphics
import Foundation

/// Converts palm-normalized hand deltas into Quartz point deltas. Reanchoring
/// never emits movement: release, clutch, tracking loss and a jump are inert.
struct RelativePointerEngine {
    private var raw: CGPoint?
    private var filtered: CGPoint?
    private var emitted: CGPoint?
    private var lastAt: Date?
    private var anchorScale: CGFloat?

    mutating func reset() {
        raw = nil; filtered = nil; emitted = nil; lastAt = nil; anchorScale = nil
    }

    mutating func process(wrist: CGPoint, scale: CGFloat, at now: Date, sensitivity: Double) -> CGVector? {
        guard MouseHandPose.valid(wrist), scale.isFinite, scale > 0.025,
              now.timeIntervalSinceReferenceDate.isFinite, sensitivity.isFinite else { reset(); return nil }
        guard let raw, let filtered, let emitted, let lastAt, let anchorScale else {
            anchor(wrist, scale: scale, at: now); return nil
        }
        let dt = now.timeIntervalSince(lastAt)
        let jump = hypot(wrist.x - raw.x, wrist.y - raw.y) / anchorScale
        guard dt > 0, dt <= AppConfig.GestureTuning.maximumFrameGap,
              jump < 0.8, scale / anchorScale > 0.6, scale / anchorScale < 1.65 else {
            reset(); return nil
        }
        self.raw = wrist; self.lastAt = now
        let alpha = 1 - exp(-dt / 0.035)
        let smooth = CGPoint(x: filtered.x + (wrist.x - filtered.x) * alpha,
                             y: filtered.y + (wrist.y - filtered.y) * alpha)
        self.filtered = smooth
        let dx = (smooth.x - emitted.x) / anchorScale
        let dy = (smooth.y - emitted.y) / anchorScale
        let distance = hypot(dx, dy)
        // Spatial hysteresis leaves a small residual around the last emitted
        // position. Slow deliberate motion accumulates; stationary noise does not.
        let deadZone: CGFloat = 0.008
        guard distance > deadZone else { return nil }
        let ratio = (distance - deadZone) / distance
        self.emitted = CGPoint(x: emitted.x + (smooth.x - emitted.x) * ratio,
                               y: emitted.y + (smooth.y - emitted.y) * ratio)
        let speed = hypot(smooth.x - filtered.x, smooth.y - filtered.y) / anchorScale / max(dt, 1.0 / 120.0)
        let acceleration = min(max((speed - 0.25) / 1.5, 0), 1)
        let gain = (180 + 1020 * acceleration) * min(max(sensitivity, 0.5), 3)
        let x = dx * ratio * gain * (AppConfig.GestureTuning.mirrorInput ? -1 : 1)
        let y = -dy * ratio * gain
        let length = hypot(x, y)
        let limit = min(1, 96 / max(length, 0.0001))
        return CGVector(dx: x * limit, dy: y * limit)
    }

    private mutating func anchor(_ wrist: CGPoint, scale: CGFloat, at now: Date) {
        raw = wrist; filtered = wrist; emitted = wrist; lastAt = now; anchorScale = scale
    }
}
