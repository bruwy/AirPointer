import CoreGraphics
import Vision
@testable import AirPointer

// Landmarks from native Vision on the original supplied images, not live camera data.
func nativeRightButtonHand() -> AirHandSnapshot {
    buttonSnapshot([
        .indexDIP: CGPoint(x: 0.488752067089081, y: 0.582540631294250),
        .indexMCP: CGPoint(x: 0.496186137199402, y: 0.565588951110840),
        .indexPIP: CGPoint(x: 0.507557034492493, y: 0.758755922317505),
        .indexTip: CGPoint(x: 0.465848565101624, y: 0.445980727672577),
        .littleDIP: CGPoint(x: 0.207380428910255, y: 0.539625763893127),
        .littleMCP: CGPoint(x: 0.117309592664242, y: 0.565741658210754),
        .littlePIP: CGPoint(x: 0.164595514535904, y: 0.693151473999023),
        .littleTip: CGPoint(x: 0.225243940949440, y: 0.451824009418488),
        .middleDIP: CGPoint(x: 0.389037996530533, y: 0.548731923103333),
        .middleMCP: CGPoint(x: 0.374694585800171, y: 0.594114661216736),
        .middlePIP: CGPoint(x: 0.390736639499664, y: 0.770533561706543),
        .middleTip: CGPoint(x: 0.380118995904922, y: 0.417037963867188),
        .ringDIP: CGPoint(x: 0.295770138502121, y: 0.514866948127747),
        .ringMCP: CGPoint(x: 0.256706833839417, y: 0.596849918365479),
        .ringPIP: CGPoint(x: 0.273284554481506, y: 0.723720669746399),
        .ringTip: CGPoint(x: 0.298390567302704, y: 0.400663197040558),
        .thumbCMC: CGPoint(x: 0.430469095706940, y: 0.276895701885223),
        .thumbIP: CGPoint(x: 0.763669192790985, y: 0.496231138706207),
        .thumbMP: CGPoint(x: 0.613402485847473, y: 0.385627806186676),
        .thumbTip: CGPoint(x: 0.908965945243835, y: 0.579512238502502),
        .wrist: CGPoint(x: 0.266937106847763, y: 0.204977214336395),
    ])
}

func nativeMiddleButtonHand() -> AirHandSnapshot {
    buttonSnapshot([
        .indexDIP: CGPoint(x: 0.825310885906219, y: 0.697963893413544),
        .indexMCP: CGPoint(x: 0.705388367176056, y: 0.408429086208344),
        .indexPIP: CGPoint(x: 0.779767990112305, y: 0.577209949493408),
        .indexTip: CGPoint(x: 0.870206773281097, y: 0.787031173706055),
        .littleDIP: CGPoint(x: 0.256689816713333, y: 0.658135056495667),
        .littleMCP: CGPoint(x: 0.342650890350342, y: 0.410993933677673),
        .littlePIP: CGPoint(x: 0.293894678354263, y: 0.551475286483765),
        .littleTip: CGPoint(x: 0.205910086631775, y: 0.791005909442902),
        .middleDIP: CGPoint(x: 0.760392487049103, y: 0.504934549331665),
        .middleMCP: CGPoint(x: 0.612653136253357, y: 0.439438700675964),
        .middlePIP: CGPoint(x: 0.685327053070068, y: 0.589492678642273),
        .middleTip: CGPoint(x: 0.799677550792694, y: 0.526079654693604),
        .ringDIP: CGPoint(x: 0.581851661205292, y: 0.683165550231934),
        .ringMCP: CGPoint(x: 0.480196863412857, y: 0.438000142574310),
        .ringPIP: CGPoint(x: 0.503338873386383, y: 0.590361714363098),
        .ringTip: CGPoint(x: 0.668194770812988, y: 0.763383984565735),
        .thumbCMC: CGPoint(x: 0.578294396400452, y: 0.077166974544525),
        .thumbIP: CGPoint(x: 0.813970506191254, y: 0.263958275318146),
        .thumbMP: CGPoint(x: 0.719074010848999, y: 0.161576986312866),
        .thumbTip: CGPoint(x: 0.812838613986969, y: 0.405502140522003),
        .wrist: CGPoint(x: 0.416656583547592, y: 0.044211864471436),
    ])
}

func nativeIndexScrollHand() -> AirHandSnapshot {
    buttonSnapshot([
        .indexDIP: CGPoint(x: 0.816015899181366, y: 0.464666306972504),
        .indexMCP: CGPoint(x: 0.642985880374908, y: 0.376004099845886),
        .indexPIP: CGPoint(x: 0.732117652893066, y: 0.471667766571045),
        .indexTip: CGPoint(x: 0.871578872203827, y: 0.401188075542450),
        .littleDIP: CGPoint(x: 0.275852054357529, y: 0.660167038440704),
        .littleMCP: CGPoint(x: 0.353653818368912, y: 0.413622498512268),
        .littlePIP: CGPoint(x: 0.313726216554642, y: 0.554524779319763),
        .littleTip: CGPoint(x: 0.230112746357918, y: 0.784776628017426),
        .middleDIP: CGPoint(x: 0.713755846023560, y: 0.671504139900208),
        .middleMCP: CGPoint(x: 0.560770332813263, y: 0.436163425445557),
        .middlePIP: CGPoint(x: 0.627270579338074, y: 0.591601729393005),
        .middleTip: CGPoint(x: 0.810684263706207, y: 0.747342109680176),
        .ringDIP: CGPoint(x: 0.552036225795746, y: 0.726937055587769),
        .ringMCP: CGPoint(x: 0.466224521398544, y: 0.446917176246643),
        .ringPIP: CGPoint(x: 0.496260732412338, y: 0.608535885810852),
        .ringTip: CGPoint(x: 0.615569770336151, y: 0.838624536991119),
        .thumbCMC: CGPoint(x: 0.604922950267792, y: 0.078087508678436),
        .thumbIP: CGPoint(x: 0.839579045772552, y: 0.253121852874756),
        .thumbMP: CGPoint(x: 0.726836144924164, y: 0.158479392528534),
        .thumbTip: CGPoint(x: 0.900719106197357, y: 0.390390932559967),
        .wrist: CGPoint(x: 0.446742177009583, y: 0.043603479862213),
    ])
}

func neutralHandForNativeReference(_ hand: AirHandSnapshot) -> AirHandSnapshot {
    var joints = hand.joints
    let wrist = hand.wrist!
    let scale = MouseHandPose.analyze(hand).scale!
    let fingers: [(VNHumanHandPoseObservation.JointName, VNHumanHandPoseObservation.JointName, VNHumanHandPoseObservation.JointName)] = [
        (.indexMCP, .indexPIP, .indexTip), (.middleMCP, .middlePIP, .middleTip),
        (.ringMCP, .ringPIP, .ringTip), (.littleMCP, .littlePIP, .littleTip)]
    for (mcp, pip, tip) in fingers {
        let base = joints[mcp]!
        let dx = base.x - wrist.x, dy = base.y - wrist.y
        let length = hypot(dx, dy)
        joints[pip] = CGPoint(x: base.x + dx / length * scale * 0.25, y: base.y + dy / length * scale * 0.25)
        joints[tip] = base
    }
    joints[.thumbTip] = CGPoint(x: wrist.x + scale * 0.5, y: wrist.y)
    return AirHandSnapshot(side: .left, joints: joints, wrist: wrist)
}
