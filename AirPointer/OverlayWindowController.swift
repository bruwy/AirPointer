import SwiftUI
import AppKit
import Combine

@MainActor
class OverlayWindowController {
    private var window: NSWindow?
    private var viewModel: ContentViewModel
    private var cancellables = Set<AnyCancellable>()
    
    init(viewModel: ContentViewModel) {
        self.viewModel = viewModel
        setupWindow()
    }
    
    private func setupWindow() {
        let win = NSWindow(
            contentRect: NSScreen.main?.frame ?? .zero,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = .floating // Above normal windows
        win.ignoresMouseEvents = true // Pass clicks through
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        // Host the Laser View in a wrapper that observes the ViewModel.
        
        let wrapper = OverlayRootView(viewModel: viewModel)
        win.contentView = NSHostingView(rootView: wrapper)
        
        self.window = win
        
        // Observe profile to show/hide
        viewModel.$activeProfile
            .sink { [weak self] profile in
                if profile == .deepwork {
                    self?.window?.orderFront(nil)
                } else {
                    self?.window?.orderOut(nil)
                }
            }
            .store(in: &cancellables)
    }
    
    private struct OverlayRootView: View {
        @ObservedObject var viewModel: ContentViewModel
        
        var body: some View {
            ZStack {
                Color.clear
                if let location = viewModel.pointerLocation {
                    LaserPointerView(location: location)
                }
            }
            .accessibilityHidden(true)
        }
    }
}
