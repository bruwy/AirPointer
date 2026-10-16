import AppKit
import Combine
import QuartzCore

/// A small, hollow, click-through panel; no full-screen surface or input monitors.
@MainActor
final class CursorFeedbackWindowController {
    private let viewModel: ContentViewModel
    private let panel: CursorFeedbackPanel
    private let halo = CursorHaloView(frame: CGRect(x: 0, y: 0,
                                                   width: CursorHaloGeometry.size, height: CursorHaloGeometry.size))
    private var cancellables = Set<AnyCancellable>()
    private var cursorTimer: Timer?
    private var shown = false
    private var visibilityRevision = 0
    private var lastCommandID: UInt = 0
    private var feedback = CursorFeedbackState()
    private var laserVisible = false

    init(viewModel: ContentViewModel) {
        self.viewModel = viewModel
        panel = CursorFeedbackPanel(contentRect: CursorHaloGeometry.frame(at: .zero),
                                    styleMask: [.borderless, .nonactivatingPanel],
                                    backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isExcludedFromWindowsMenu = true
        panel.animationBehavior = .none
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = halo

        viewModel.$cursorFeedback.combineLatest(viewModel.$pointerLocation)
            .sink { [weak self] feedback, laser in
                guard let self else { return }
                self.feedback = feedback
                self.laserVisible = laser != nil
                self.render()
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.render() }
            .store(in: &cancellables)
    }

    deinit { cursorTimer?.invalidate() }

    private func render() {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        halo.setContrast(increased: NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast,
                         reduceMotion: reduceMotion, pressed: feedback.pressedButton != nil)
        let visible = feedback.phase != .hidden && (!laserVisible || feedback.pressedButton != nil)
        if visible != shown {
            shown = visible
            visibilityRevision &+= 1
            let revision = visibilityRevision
            if visible {
                positionAtCursor()
                panel.orderFront(nil)
                halo.show(reduceMotion: reduceMotion)
                startTimer()
            } else {
                halo.hide(reduceMotion: reduceMotion)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) { [weak self] in
                    guard let self, self.visibilityRevision == revision, !self.shown else { return }
                    self.panel.orderOut(nil)
                    self.cursorTimer?.invalidate()
                    self.cursorTimer = nil
                }
            }
        }
        if visible, feedback.phase == .recognized, feedback.commandID != lastCommandID {
            halo.confirm(reduceMotion: reduceMotion)
        }
        lastCommandID = feedback.commandID
    }

    private func startTimer() {
        guard cursorTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.viewModel.expireTrackingState()
                self?.positionAtCursor()
            }
        }
        timer.tolerance = 0.005
        RunLoop.main.add(timer, forMode: .common)
        cursorTimer = timer
    }

    private func positionAtCursor() {
        let cursor = NSEvent.mouseLocation
        let frame = CursorHaloGeometry.frame(at: cursor)
        if panel.frame != frame { panel.setFrame(frame, display: false) }
        let scale = NSScreen.screens.first { $0.frame.contains(cursor) }?.backingScaleFactor
            ?? panel.backingScaleFactor
        halo.setScale(scale)
    }
}

@MainActor
private final class CursorFeedbackPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class CursorHaloView: NSView {
    private let ring = CALayer()
    private let outline = CAShapeLayer()
    private let stroke = CAShapeLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        setAccessibilityElement(false)
        ring.frame = bounds
        ring.opacity = 0
        layer?.addSublayer(ring)
        let path = CGPath(ellipseIn: bounds.insetBy(dx: 14, dy: 14), transform: nil)
        for shape in [outline, stroke] {
            shape.frame = bounds
            shape.path = path
            shape.fillColor = nil
            ring.addSublayer(shape)
        }
    }

    required init?(coder: NSCoder) { return nil }

    func setScale(_ scale: CGFloat) {
        for target in [layer, ring, outline, stroke].compactMap({ $0 }) {
            if target.contentsScale != scale { target.contentsScale = scale }
        }
    }

    func setContrast(increased: Bool, reduceMotion: Bool, pressed: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        outline.strokeColor = NSColor.black.withAlphaComponent(increased ? 0.95 : 0.6).cgColor
        outline.lineWidth = pressed ? 5 : (increased ? 4 : 3)
        stroke.strokeColor = NSColor.white.withAlphaComponent(increased ? 1 : 0.8).cgColor
        stroke.lineWidth = pressed ? 3 : (increased ? 2 : 1.4)
        CATransaction.commit()
        if reduceMotion {
            ring.removeAnimation(forKey: "entry")
            ring.removeAnimation(forKey: "confirmation")
        }
    }

    func show(reduceMotion: Bool) {
        fade(to: 1, duration: reduceMotion ? 0.08 : 0.14)
        if !reduceMotion {
            let entry = CABasicAnimation(keyPath: "transform.scale")
            entry.fromValue = ring.presentation()?.value(forKeyPath: "transform.scale") ?? 0.92
            entry.toValue = 1
            entry.duration = 0.14
            entry.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ring.add(entry, forKey: "entry")
        }
    }

    func hide(reduceMotion: Bool) {
        ring.removeAnimation(forKey: "entry")
        ring.removeAnimation(forKey: "confirmation")
        stroke.removeAnimation(forKey: "emphasis")
        fade(to: 0, duration: reduceMotion ? 0.08 : 0.14)
    }

    func confirm(reduceMotion: Bool) {
        if reduceMotion {
            let emphasis = CAKeyframeAnimation(keyPath: "opacity")
            emphasis.values = [1, 0.65, 1]
            emphasis.keyTimes = [0, 0.4, 1]
            emphasis.duration = CursorFeedbackState.confirmationDuration
            stroke.add(emphasis, forKey: "emphasis")
        } else {
            let pulse = CAKeyframeAnimation(keyPath: "transform.scale")
            pulse.values = [ring.presentation()?.value(forKeyPath: "transform.scale") ?? 1, 1.12, 1]
            pulse.keyTimes = [0, 0.4, 1]
            pulse.duration = CursorFeedbackState.confirmationDuration
            pulse.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeInEaseOut)]
            ring.removeAnimation(forKey: "entry")
            ring.add(pulse, forKey: "confirmation")
        }
    }

    private func fade(to opacity: Float, duration: TimeInterval) {
        let current = ring.presentation()?.opacity ?? ring.opacity
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.opacity = opacity
        CATransaction.commit()
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = current
        fade.toValue = opacity
        fade.duration = duration
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        ring.add(fade, forKey: "visibility")
    }
}
