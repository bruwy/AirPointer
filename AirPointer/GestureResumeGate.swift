import CoreGraphics
import Foundation

/// After a global pause, each hand must show a complete neutral pose before
/// its observations can reach any recognizer. A missing hand never rearms it.
struct GestureResumeGate {
    private(set) var waiting = Set<AirHandSide>()
    private var neutralSince: [AirHandSide: Date] = [:]

    mutating func requireNeutral() {
        waiting = [.left, .right]
        neutralSince = [:]
    }

    mutating func interrupt() { neutralSince = [:] }

    mutating func filter(_ frame: AirFrame) -> AirFrame {
        var accepted: [AirHandSnapshot] = []
        for side in [AirHandSide.left, .right] {
            guard let hand = frame.hand(for: side) else {
                neutralSince[side] = nil
                continue
            }
            if waiting.contains(side) {
                guard isNeutral(hand) else { neutralSince[side] = nil; continue }
                if neutralSince[side] == nil { neutralSince[side] = frame.timestamp }
                guard let since = neutralSince[side],
                      frame.timestamp.timeIntervalSince(since) >= AppConfig.MouseTuning.neutralHold else { continue }
                waiting.remove(side)
                neutralSince[side] = nil
            }
            accepted.append(hand)
        }
        return AirFrame(timestamp: frame.timestamp, hands: accepted)
    }

    private func isNeutral(_ hand: AirHandSnapshot) -> Bool {
        if hand.side == .left { return LeftButtonPose.analyze(hand) == .neutral }
        let evidence = MouseHandPose.analyze(hand)
        guard evidence.fingers.allSatisfy({ $0 == .extended }),
              let pinch = HandPoseMetrics.pinchDistanceNormalized(from: hand.joints) else { return false }
        return pinch > AppConfig.GestureTuning.pinchThresholdOff
    }
}
