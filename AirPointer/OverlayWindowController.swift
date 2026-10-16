import SwiftUI
import AppKit
import Combine

@MainActor
class OverlayWindowController {
    private var window: NSWindow?
    private let viewModel: ContentViewModel
    private var cancellables = Set<AnyCancellable>()
    
    init(viewModel: ContentViewModel) {
        self.viewModel = viewModel
        viewModel.$activeProfile.combineLatest(viewModel.$pointerLocation)
            .sink { [weak self] profile, location in
                guard let self else { return }
                if profile == .deepwork && location != nil {
                    if self.window == nil { self.setupWindow() }
                    self.window?.orderFront(nil)
                } else { self.window?.orderOut(nil) }
            }
            .store(in: &cancellables)
    }
    
    private func setupWindow() {
        let win = LaserOverlayPanel(
            contentRect: NSScreen.main?.frame ?? .zero,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        win.isOpaque = false
        win.backgroundColor = .clear
        win.level = .floating // Above normal windows
        win.ignoresMouseEvents = true // Pass clicks through
        win.hidesOnDeactivate = false
        win.isReleasedWhenClosed = false
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        // Host the Laser View in a wrapper that observes the ViewModel.
        
        let wrapper = OverlayRootView(viewModel: viewModel)
        win.contentView = NSHostingView(rootView: wrapper)
        
        self.window = win
        
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

@MainActor
private final class LaserOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
