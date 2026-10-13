import CoreGraphics
import Foundation

/// Both clicks commit on a closed-hand release. An open palm always clutches
/// and cancels pending clicks, including a 1/2-finger transition on the way up.
@MainActor
final class LeftMouseEngine {
    struct Output {
        var delta: CGVector?
        var rightClick: Bool?
        var status = "Close fingers to begin"
        var evidence = ""
    }
    private var pointer = RelativePointerEngine()
    private var lastAt: Date?
    private var armed = false
    private var closedSince: Date?
    private var candidate: MouseHandPose.Pose?
    private var stableTime: TimeInterval = 0
    private var stableFrames = 0
    private var uncertainSince: Date?
    private var pendingClick: Bool?
    private var sawTwo = false
    private var scrollSuspended = false

    func reset() {
        pointer.reset(); lastAt = nil; armed = false; closedSince = nil
        candidate = nil; stableTime = 0; stableFrames = 0; uncertainSince = nil
        pendingClick = nil; sawTwo = false; scrollSuspended = false
    }

    func process(frame: AirFrame, reservePinch: Bool, sensitivity: Double = 1.2) -> Output {
        let now = frame.timestamp
        guard now.timeIntervalSinceReferenceDate.isFinite else { reset(); return Output(status: "Invalid timestamp") }
        let dt = lastAt.map { now.timeIntervalSince($0) } ?? 0
        if lastAt != nil && (dt <= 0 || dt > AppConfig.GestureTuning.maximumFrameGap) {
            let watermark = max(lastAt!, now)
            reset(); lastAt = watermark
            return Output(status: "Tracking interrupted — close fingers")
        }
        lastAt = now
        guard let hand = frame.hand(for: .left) else { reset(); return Output(status: "Left hand missing") }
        let evidence = MouseHandPose.analyze(hand)
        var output = Output(evidence: evidence.summary)
        guard evidence.pose != .unknown, let scale = evidence.scale, let wrist = hand.wrist else {
            reset(); output.status = "Joints missing — close fingers"; return output
        }
        // Thumb is irrelevant to finger counts. Only the Deepwork scroll
        // arbitration needs it; an incomplete pinch cannot turn into a click.
        if reservePinch {
            guard let pinch = HandPoseMetrics.pinchDistanceNormalized(from: hand.joints) else {
                reset(); output.status = "Scroll evidence incomplete"; return output
            }
            if pinch < AppConfig.GestureTuning.pinchThresholdOff,
               evidence.pose != .closed {
                reset(); lastAt = now; scrollSuspended = true
                output.status = "Scroll — cursor parked"; return output
            }
        }
        if evidence.pose == .clutch {
            reset(); lastAt = now
            output.status = "Hand open — reposition freely"; return output
        }
        if evidence.pose == .closed {
            if closedSince == nil { closedSince = now; pointer.reset() }
            candidate = nil; stableTime = 0; stableFrames = 0; uncertainSince = nil
            let ready = now.timeIntervalSince(closedSince!) >= AppConfig.MouseTuning.neutralHold
            guard ready else { output.status = "Closing — rearming"; return output }
            if let click = pendingClick, armed, !scrollSuspended {
                output.rightClick = click
                output.status = click ? "Right click recognized" : "Left click recognized"
                pointer.reset()
            } else {
                output.status = "Trackpad ready"
                output.delta = pointer.process(wrist: wrist, scale: scale, at: now, sensitivity: sensitivity)
            }
            pendingClick = nil; sawTwo = false; armed = true; scrollSuspended = false
            return output
        }
        closedSince = nil
        pointer.reset() // park the cursor while forming or releasing a click
        guard armed, !scrollSuspended else { output.status = "Close fingers to arm"; return output }
        if evidence.fingers.prefix(2).allSatisfy({ $0 == .extended }) {
            if !sawTwo { pendingClick = nil }
            sawTwo = true
        }
        if evidence.fingers[2] == .extended || evidence.fingers[3] == .extended {
            pendingClick = nil; armed = false
        }
        if evidence.pose == .transition {
            if uncertainSince == nil { uncertainSince = now }
            // A short ambiguous geometry frame pauses, never advances, evidence.
            // A real missing hand/joint above cancels immediately.
            if now.timeIntervalSince(uncertainSince!) > 0.10 {
                candidate = nil; stableTime = 0; stableFrames = 0
                // Preserve a confirmed click through the gradual descent of
                // the index; other raised fingers cannot become a single.
                if evidence.fingers.dropFirst().contains(.extended) && pendingClick == false { pendingClick = nil }
            }
            output.status = pendingClick == nil ? "Adjust fingers" : "Close fingers to click"
            return output
        }
        let resumingEvidence = uncertainSince != nil
        uncertainSince = nil
        if candidate != evidence.pose {
            candidate = evidence.pose; stableTime = 0; stableFrames = 1
        } else {
            if !resumingEvidence { stableTime += min(dt, 1.0 / 15.0) }
            stableFrames += 1
        }
        if stableTime >= AppConfig.MouseTuning.poseHold && stableFrames >= 3 {
            if evidence.pose == .two { pendingClick = true }
            else if !sawTwo { pendingClick = false }
        }
        output.status = pendingClick == nil ? "Hold fingers briefly" : (pendingClick! ? "Close for RIGHT click" : "Close for LEFT click")
        return output
    }
}
