import SwiftUI
import AVFoundation

/// Uma NSView que simplesmente exibe a camada de preview da sessão da câmera.
class CameraPreviewView: NSView {
    private let previewLayer: AVCaptureVideoPreviewLayer

    init(session: AVCaptureSession) {
        self.previewLayer = AVCaptureVideoPreviewLayer(session: session)
        self.previewLayer.videoGravity = .resizeAspectFill
        super.init(frame: .zero)
        self.wantsLayer = true
        self.layer?.addSublayer(previewLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layout() {
        super.layout()
        previewLayer.frame = self.bounds
    }
    
    // Propriedade para acessar a camada de vídeo, se necessário
    var videoLayer: AVCaptureVideoPreviewLayer { previewLayer }
}


/// A View Representable que integra a CameraPreviewView ao SwiftUI.
struct CameraView: NSViewRepresentable {

    /// Engine que provê a sessão de captura da câmera.
    let engine: AirCore

    // MARK: - NSViewRepresentable

    func makeNSView(context _: Context) -> CameraPreviewView {
        let view = CameraPreviewView(session: engine.session)

        // Configura o espelhamento do vídeo para uma experiência de "espelho" mais intuitiva.
        // O HandTracker já lida com a lógica de coordenadas internamente.
        if let connection = view.videoLayer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        
        return view
    }

    func updateNSView(_ nsView: CameraPreviewView, context: Context) {
    }
}
