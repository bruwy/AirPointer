import SwiftUI
import Vision

struct HandSkeletonOverlayView: View {
	// Dados das mãos vindos do Tracker
	let hands: [String: [VNHumanHandPoseObservation.JointName: CGPoint]]
	
	// Configurações de Espelhamento (padrão true para câmera frontal)
	var mirrorHorizontally: Bool = true
	
	// Tamanho do buffer de vídeo original (Padrão VGA 640x480)
	// Se mudar o preset no HandTracker, mude aqui também.
	var videoSize: CGSize = CGSize(width: 640, height: 480)

	// Definição das conexões dos dedos para desenhar as linhas
	private static let fingerChains: [[VNHumanHandPoseObservation.JointName]] = [
		[.thumbTip, .thumbIP, .thumbMP, .thumbCMC],       // Polegar
		[.indexTip, .indexDIP, .indexPIP, .indexMCP],     // Indicador
		[.middleTip, .middleDIP, .middlePIP, .middleMCP], // Médio
		[.ringTip, .ringDIP, .ringPIP, .ringMCP],         // Anelar
		[.littleTip, .littleDIP, .littlePIP, .littleMCP]  // Mínimo
	]

	var body: some View {
		// O Canvas fornece o 'size' real disponível na renderização
		Canvas { context, size in
			// 1. Lógica de Aspect Fill (Zoom para preencher)
			// Descobre qual dimensão precisa escalar mais para cobrir a tela
			let scaleX = size.width / videoSize.width
			let scaleY = size.height / videoSize.height
			let scale = max(scaleX, scaleY)
			
			let zoomedWidth = videoSize.width * scale
			let zoomedHeight = videoSize.height * scale
			
			// 2. Calcula offsets para centralizar (Center Crop)
			// Isso alinha o esqueleto com o vídeo que também está em AspectFill
			let xOffset = (zoomedWidth - size.width) / 2
			let yOffset = (zoomedHeight - size.height) / 2
			
			// Função local de projeção de pontos
			func project(_ p: CGPoint) -> CGPoint {
				// a. Vision é (0,0) no canto inferior esquerdo. SwiftUI é superior esquerdo.
				//    Invertemos Y: (1 - p.y)
				let yNorm = 1 - p.y
				
				// b. Espelhamento (Vision retorna 0..1 da esq para dir da imagem processada)
				let xNorm = mirrorHorizontally ? (1 - p.x) : p.x
				
				// c. Escala e aplica o offset do Zoom
				let xZoomed = xNorm * zoomedWidth
				let yZoomed = yNorm * zoomedHeight
				
				return CGPoint(x: xZoomed - xOffset, y: yZoomed - yOffset)
			}

			// 3. Desenho das Mãos
			for (label, joints) in hands {
				// Diferencia cor por mão (Esquerda/Direita)
				let color: Color = (label == "right") ? .blue : .green
				let wrist = joints[.wrist]
				
				// Desenha as Linhas (Ossos)
				var path = Path()
				for finger in Self.fingerChains {
					guard let tip = joints[finger[0]] else { continue }
					
					path.move(to: project(tip))
					
					// Conecta as falanges
					for joint in finger.dropFirst() {
						if let pt = joints[joint] {
							path.addLine(to: project(pt))
						}
					}
					
					// Conecta a base do dedo ao pulso (Metacarpo)
					if let last = finger.last, let base = joints[last], let w = wrist {
						path.move(to: project(base))
						path.addLine(to: project(w))
					}
				}
				
				// Renderiza as linhas
				context.stroke(
					path,
					with: .color(color),
					style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
				)
				
				// Desenha os Pontos (Articulações)
				for (_, point) in joints {
					let p = project(point)
					// Centraliza o círculo no ponto (-4)
					let rect = CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)
					context.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.8)))
				}
			}
		}
		// Permite que os toques passem através do Canvas para a UI atrás (se houver)
		.allowsHitTesting(false)
		.accessibilityHidden(true)
	}
}
