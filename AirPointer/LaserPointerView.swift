import SwiftUI

struct LaserPointerView: View {
    let location: CGPoint?
    
    var body: some View {
        GeometryReader { geo in
            if let loc = location {
                // Convert normalized Vision coordinates (Y up) to SwiftUI (Y down)
                // Vision: (0,0) is Bottom-Left. SwiftUI: (0,0) is Top-Left.
                // Mirror horizontally to match the mirrored camera preview.
                let x = (1 - loc.x) * geo.size.width
                let y = (1 - loc.y) * geo.size.height
                
                ZStack {
                    // Outer Glow
                    Circle()
                        .fill(RadialGradient(colors: [.red.opacity(0.4), .clear], center: .center, startRadius: 5, endRadius: 30))
                        .frame(width: 60, height: 60)
                    
                    // Core
                    Circle()
                        .fill(Color.red)
                        .frame(width: 10, height: 10)
                        .shadow(color: .red, radius: 5)
                }
                .position(x: x, y: y)
                .animation(.linear(duration: 0.05), value: loc) // Smooth movement
            }
        }
		.allowsHitTesting(false) // Pass clicks through
		.accessibilityHidden(true)
	}
}
