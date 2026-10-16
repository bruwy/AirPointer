import CoreGraphics
import Foundation

/// Wrist movement keeps the same anchor while fingers form or hold a button.
@MainActor
final class LeftMouseEngine {
    struct Output {
        var delta: CGVector?
        var desiredButton: MouseButton?
        var status = "Close fingers to begin"
        var evidence = ""
        var buttonStatus = "Buttons: left hand unavailable"
        var isReady = false
        var isPaused = false
    }
    private var pointer = RelativePointerEngine()
    private let buttons = LeftButtonEngine()
    private var lastAt: Date?
    private var armed = false
    private var closedSince: Date?

    func reset() {
        pointer.reset(); buttons.reset(); lastAt = nil
        armed = false; closedSince = nil
    }

    func process(frame: AirFrame, reservePinch: Bool, sensitivity: Double = 1.2) -> Output {
        let now = frame.timestamp
        guard now.timeIntervalSinceReferenceDate.isFinite else { reset(); return Output(status: "Invalid timestamp") }
        if let lastAt {
            let dt = now.timeIntervalSince(lastAt)
            if dt <= 0 || dt > AppConfig.GestureTuning.maximumFrameGap {
                let watermark = max(lastAt, now)
                reset(); self.lastAt = watermark
                return Output(status: "Tracking interrupted — close fingers")
            }
        }
        lastAt = now
        guard let hand = frame.hand(for: .left) else {
            reset()
            return Output(status: "Left hand missing", buttonStatus: frame.hand(for: .right) == nil
                ? "Buttons: left hand unavailable" : "Buttons: no left hand — right hand tracked")
        }
        let evidence = MouseHandPose.analyze(hand)
        var output = Output(evidence: evidence.summary)
        guard evidence.pose != .unknown, !evidence.fingers.contains(.missing),
              let scale = evidence.scale, let wrist = hand.wrist else {
            reset(); output.status = "Joints missing — close fingers"
            output.buttonStatus = "Buttons: incomplete finger evidence"; return output
        }
        let buttonPose = LeftButtonPose.analyze(hand, holding: buttons.heldButton)
        // Keep the existing index-pinch scroll and closed-hand movement arbitration.
        if reservePinch, evidence.pose != .closed,
           let pinch = HandPoseMetrics.pinchDistanceNormalized(from: hand.joints),
           pinch < AppConfig.GestureTuning.pinchThresholdOff {
            reset(); lastAt = now
            output.status = "Scroll — cursor parked"; output.isPaused = true
            output.buttonStatus = "Buttons: released for index scroll"; return output
        }
        let clutch = evidence.fingers.allSatisfy({ $0 == .extended }) && buttonPose.button == nil
        let button = buttons.process(frame: frame, clutch: clutch)
        output.buttonStatus = buttons.diagnosticStatus
        output.evidence += " · " + buttons.diagnosticStatus + "\n" + LeftButtonPose.diagnosticEvidence(hand)
        if clutch {
            pointer.reset(); armed = false; closedSince = nil
            output.status = "Hand open — reposition freely"; output.isPaused = true; return output
        }
        if !armed {
            guard evidence.pose == .closed, buttonPose.button == nil else {
                closedSince = nil; pointer.reset()
                output.status = "Close fingers to arm"; return output
            }
            if closedSince == nil { closedSince = now }
            guard now.timeIntervalSince(closedSince!) >= AppConfig.MouseTuning.neutralHold else {
                output.status = "Closing — rearming"; return output
            }
            armed = true
        }
        output.isReady = true
        output.desiredButton = button.desiredButton
        output.status = button.desiredButton.map { "\($0.title) pressed — move to drag" } ?? "Trackpad ready"
        output.delta = pointer.process(wrist: wrist, scale: scale, at: now, sensitivity: sensitivity)
        if !pointer.isAnchored {
            reset()
            return Output(status: "Tracking jump — close fingers", evidence: evidence.summary)
        }
        return output
    }
}
