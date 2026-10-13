import Foundation
import CoreGraphics

/// Suaviza o movimento do cursor usando suavização exponencial.
final class CursorSmoother {
    private var last: CGPoint?
    private let smoothingFactor: CGFloat

    /// Inicializa o suavizador com um fator específico.
    /// - Parameter smoothingFactor: O peso a ser dado ao ponto atual em cada passo (ex: 0.2 para 20%).
    init(smoothingFactor: CGFloat) {
        // Garante que o fator esteja em um intervalo razoável [0, 1]
        self.smoothingFactor = min(max(smoothingFactor, 0), 1)
    }
    
    func smooth(_ current: CGPoint) -> CGPoint {
        guard let prev = last else {
            last = current
            return current
        }
        
        let newX = prev.x * (1 - smoothingFactor) + current.x * smoothingFactor
        let newY = prev.y * (1 - smoothingFactor) + current.y * smoothingFactor
        
        let out = CGPoint(x: newX, y: newY)
        last = out
        return out
    }
    
    /// Reseta o ponto anterior, útil quando a mão é perdida e reaparece.
    func reset() {
        last = nil
    }
}
