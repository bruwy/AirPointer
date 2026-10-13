import CoreGraphics
import Foundation
import Vision

/// Local, rotation-invariant finger evidence. No camera or event dependencies.
enum MouseHandPose {
    enum Finger: String { case extended = "up", curled = "down", uncertain = "?", missing = "missing" }
    enum Pose: String { case closed, one, two, clutch, transition, unknown }
    struct Evidence {
        let pose: Pose
        let fingers: [Finger]
        let scale: CGFloat?
        var summary: String {
            zip(["I", "M", "R", "L"], fingers).map { "\($0):\($1.rawValue)" }.joined(separator: " ")
        }
    }

    static func analyze(_ hand: AirHandSnapshot) -> Evidence {
        let joints = hand.joints
        guard let wrist = hand.wrist, valid(wrist),
              let middle = joints[.middleMCP], valid(middle),
              let index = joints[.indexMCP], valid(index),
              let little = joints[.littleMCP], valid(little) else {
            return Evidence(pose: .unknown, fingers: Array(repeating: .missing, count: 4), scale: nil)
        }
        let scale = hypot(middle.x - wrist.x, middle.y - wrist.y)
        guard scale > 0.025 else {
            return Evidence(pose: .unknown, fingers: Array(repeating: .uncertain, count: 4), scale: nil)
        }
        let ring = joints[.ringMCP] ?? CGPoint(x: (middle.x + little.x) / 2, y: (middle.y + little.y) / 2)
        let names: [(VNHumanHandPoseObservation.JointName, VNHumanHandPoseObservation.JointName,
                     VNHumanHandPoseObservation.JointName)] = [
            (.indexPIP, .indexDIP, .indexTip), (.middlePIP, .middleDIP, .middleTip),
            (.ringPIP, .ringDIP, .ringTip), (.littlePIP, .littleDIP, .littleTip)
        ]
        let fingers = zip([index, middle, ring, little], names).map { mcp, names in
            classify(wrist: wrist, mcp: mcp, pip: joints[names.0], dip: joints[names.1],
                     tip: joints[names.2], scale: scale)
        }
        let pose: Pose
        // Three raised fingers suffice to lift the virtual trackpad, even if
        // the fourth is hidden. Clutch only cancels; it cannot authorize a click.
        if fingers.filter({ $0 == .extended }).count >= 3 { pose = .clutch }
        else if fingers.contains(.missing) { pose = .unknown }
        else if fingers.allSatisfy({ $0 == .curled }) { pose = .closed }
        else if fingers == [.extended, .curled, .curled, .curled] { pose = .one }
        else if fingers == [.extended, .extended, .curled, .curled] { pose = .two }
        else { pose = .transition }
        return Evidence(pose: pose, fingers: fingers, scale: scale)
    }

    private static func classify(wrist: CGPoint, mcp: CGPoint, pip: CGPoint?, dip: CGPoint?,
                                 tip: CGPoint?, scale: CGFloat) -> Finger {
        guard valid(mcp) else { return .missing }
        let base = distance(wrist, mcp)
        if let tip {
            guard valid(tip) else { return .missing }
            let reach = (distance(wrist, tip) - base) / scale
            if let pip {
                guard valid(pip) else { return .missing }
                let proximal = distance(mcp, pip)
                guard proximal > scale * 0.08 else { return .uncertain }
                let distal = distance(pip, tip)
                let straightness = distance(mcp, tip) / max(proximal + distal, scale * 0.05)
                let beyondPIP = dot(vector(mcp, pip), vector(pip, tip)) / (proximal * proximal)
                // Curl evidence has priority: bent fingers can still put a tip
                // farther from the wrist than the old universal 1.05 threshold.
                if reach < 0.13 || straightness < 0.65 || beyondPIP < -0.10 { return .curled }
                if reach > 0.28 && straightness > 0.84 && beyondPIP > 0.18 { return .extended }
                return .uncertain
            }
            // Missing PIP is not invented. A conservative radial fallback uses
            // this finger's own knuckle and a wide uncertainty band.
            if reach < 0.12 { return .curled }
            if reach > 0.55 { return .extended }
            return .uncertain
        }
        // A hidden curled fingertip can be supported by three visible joints.
        // Missing index/middle tips can never be inferred as raised fingers.
        if let pip, let dip, valid(pip), valid(dip) {
            let a = vector(mcp, pip), b = vector(pip, dip)
            let denominator = hypot(a.dx, a.dy) * hypot(b.dx, b.dy)
            if denominator > scale * scale * 0.006,
               dot(a, b) / denominator < -0.20,
               distance(wrist, dip) < base + scale * 0.18 { return .curled }
        }
        return .missing
    }

    static func valid(_ p: CGPoint) -> Bool {
        p.x.isFinite && p.y.isFinite && (0...1).contains(p.x) && (0...1).contains(p.y)
    }
    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
    private static func vector(_ a: CGPoint, _ b: CGPoint) -> CGVector { CGVector(dx: b.x - a.x, dy: b.y - a.y) }
    private static func dot(_ a: CGVector, _ b: CGVector) -> CGFloat { a.dx * b.dx + a.dy * b.dy }
}
