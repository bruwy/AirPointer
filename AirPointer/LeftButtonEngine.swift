import CoreGraphics
import Foundation
import Vision

/// Left-hand button poses, independent of pointer movement or delivery.
enum LeftButtonPose {
    enum Pose: Equatable {
        case button(MouseButton), neutral, transition, unknown
        var button: MouseButton? {
            if case .button(let button) = self { return button }
            return nil
        }
    }

    static func analyze(_ hand: AirHandSnapshot, holding: MouseButton? = nil) -> Pose {
        let evidence = MouseHandPose.analyze(hand)
        let joints = hand.joints
        guard let scale = evidence.scale, let wrist = hand.wrist,
              let thumb = joints[.thumbTip], MouseHandPose.valid(thumb),
              !evidence.fingers.contains(.missing) else { return .unknown }
        let curled = evidence.fingers.allSatisfy({ $0 == .curled })
        let radialReach = distance(wrist, thumb) / scale
        // Visible bent bones can prove a relaxed closed hand even when tips or
        // intermediate thumb joints are occluded. They never authorize a press.
        // Use the same boundary as the positive thumb-up pose. The old 0.90
        // boundary left a dead band where the pointer armed but buttons never did.
        let thumbUpBoundary: CGFloat = holding == .right ? 0.95 : 1.05
        if curled, radialReach <= thumbUpBoundary { return .neutral }
        guard let index = joints[.indexTip], MouseHandPose.valid(index),
              let middle = joints[.middleTip], MouseHandPose.valid(middle),
              let ring = joints[.ringTip], MouseHandPose.valid(ring) else { return .unknown }
        let indexDistance = distance(thumb, index) / scale
        let middleDistance = distance(thumb, middle) / scale
        let ringDistance = distance(thumb, ring) / scale
        // Native Vision puts touching fingertips up to 0.27 palm lengths apart.
        let ringContact = ringDistance < (holding == .left ? 0.40 : 0.30)
        let middleContact = middleDistance < (holding == .middle ? 0.40 : 0.30)
        // Keep the index free: thumb+index is reserved for Deepwork scrolling.
        if ringContact, indexDistance > 0.38, middleDistance > 0.38,
           [0, 1, 3].allSatisfy({ evidence.fingers[$0] == .extended }) { return .button(.left) }
        if middleContact, indexDistance > 0.38, ringDistance > 0.38,
           [0, 2, 3].allSatisfy({ evidence.fingers[$0] == .extended }) { return .button(.middle) }
        if curled {
            guard let mp = joints[.thumbMP], MouseHandPose.valid(mp),
                  let ip = joints[.thumbIP], MouseHandPose.valid(ip) else { return .unknown }
            let length = distance(mp, ip) + distance(ip, thumb)
            guard length > scale * 0.2 else { return .unknown }
            let straightness = distance(mp, thumb) / length
            let reach = distance(mp, thumb) / scale
            let held = holding == .right
            if straightness > (held ? 0.80 : 0.90), reach > (held ? 0.35 : 0.45),
               radialReach > (held ? 0.95 : 1.05) { return .button(.right) }
            return .transition
        }
        if evidence.fingers.allSatisfy({ $0 == .extended }),
           indexDistance > 0.38, middleDistance > 0.38, ringDistance > 0.38 { return .neutral }
        return .transition
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    static func diagnosticEvidence(_ hand: AirHandSnapshot) -> String {
        guard let thumb = hand.joints[.thumbTip], let wrist = hand.wrist,
              let scale = MouseHandPose.analyze(hand).scale else { return "Thumb/palm unavailable" }
        let distances = [hand.joints[.indexTip], hand.joints[.middleTip], hand.joints[.ringTip]].map { tip in
            tip.map { String(format: "%.2f", distance(thumb, $0) / scale) } ?? "missing"
        }
        let thumbBones = hand.joints[.thumbMP] != nil && hand.joints[.thumbIP] != nil ? "visible" : "occluded"
        return "Thumb I/M/R: \(distances.joined(separator: "/")) · reach \(String(format: "%.2f", distance(wrist, thumb) / scale)) · bones \(thumbBones)"
    }
}

/// Desired button state only. The caller owns balanced OS down/up delivery.
@MainActor
final class LeftButtonEngine {
    struct Output {
        var desiredButton: MouseButton?
        var isReady = false
    }

    private(set) var heldButton: MouseButton?
    private var lastAt: Date?
    private var candidate: MouseButton?
    private var stableTime: TimeInterval = 0
    private var stableFrames = 0
    private var releaseSince: Date?
    private var neutralSince: Date?
    private var needsNeutral = true
    private var latestPose: LeftButtonPose.Pose = .unknown

    var diagnosticStatus: String {
        let pose = latestPose.button?.title ?? String(describing: latestPose)
        let state = heldButton != nil ? "held" : (needsNeutral ? "awaiting neutral" : (candidate != nil ? "confirming" : "ready"))
        return "Buttons: \(state) · pose: \(pose)"
    }

    func reset() {
        heldButton = nil; lastAt = nil; candidate = nil
        stableTime = 0; stableFrames = 0; releaseSince = nil
        neutralSince = nil; needsNeutral = true
        latestPose = .unknown
    }

    func process(frame: AirFrame, clutch: Bool = false) -> Output {
        let now = frame.timestamp
        guard now.timeIntervalSinceReferenceDate.isFinite else { reset(); return Output() }
        let dt = lastAt.map { now.timeIntervalSince($0) } ?? 0
        if let lastAt, dt <= 0 || dt > AppConfig.GestureTuning.maximumFrameGap {
            let watermark = max(lastAt, now)
            reset(); self.lastAt = watermark
            return Output()
        }
        lastAt = now
        guard let hand = frame.hand(for: .left) else {
            reset(); return Output()
        }
        if clutch {
            // A full open hand releases immediately, then accumulates neutral
            // evidence across frames. Never resurrect a hold after a brief opening.
            heldButton = nil; candidate = nil; stableTime = 0; stableFrames = 0
            releaseSince = nil; needsNeutral = true
        }
        let pose = LeftButtonPose.analyze(hand, holding: heldButton)
        latestPose = pose
        guard pose != .unknown else { reset(); return Output() }
        if let heldButton {
            if pose.button == heldButton {
                releaseSince = nil
                return Output(desiredButton: heldButton, isReady: true)
            }
            if pose.button != nil {
                // Release the old button before confirming a replacement.
                self.heldButton = nil
            } else {
                if releaseSince == nil { releaseSince = now }
                guard now.timeIntervalSince(releaseSince!) >= 0.06 else {
                    return Output(desiredButton: heldButton, isReady: true)
                }
                self.heldButton = nil
            }
            releaseSince = nil; candidate = nil; stableTime = 0; stableFrames = 0
        }
        if pose == .neutral {
            candidate = nil; stableTime = 0; stableFrames = 0
            if neutralSince == nil { neutralSince = now }
            if now.timeIntervalSince(neutralSince!) >= 0.10 { needsNeutral = false }
            return Output(isReady: !needsNeutral)
        }
        neutralSince = nil
        guard !needsNeutral, let button = pose.button else {
            candidate = nil; stableTime = 0; stableFrames = 0
            return Output()
        }
        if candidate != button {
            candidate = button; stableTime = 0; stableFrames = 1
        } else {
            stableTime += min(dt, 1.0 / 15)
            stableFrames += 1
        }
        if stableTime >= 0.16, stableFrames >= AppConfig.MouseTuning.minimumStableFrames {
            heldButton = button
            candidate = nil; stableTime = 0; stableFrames = 0
        }
        return Output(desiredButton: heldButton, isReady: heldButton != nil)
    }
}
