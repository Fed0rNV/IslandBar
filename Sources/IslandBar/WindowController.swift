import AppKit
import Combine
import QuartzCore
import SwiftUI

struct ScreenLayout {
    let screen: NSScreen
    let hasPhysicalNotch: Bool
    let notchWidth: CGFloat
    let notchHeight: CGFloat

    static func preferred() -> ScreenLayout? {
        guard !NSScreen.screens.isEmpty else { return nil }
        let screen = NSScreen.screens.max { lhs, rhs in
            lhs.safeAreaInsets.top < rhs.safeAreaInsets.top
        } ?? NSScreen.main ?? NSScreen.screens[0]

        let left = screen.auxiliaryTopLeftArea
        let right = screen.auxiliaryTopRightArea
        let gap: CGFloat
        if let left, let right {
            gap = right.minX - left.maxX
        } else {
            gap = 0
        }
        let hasNotch = screen.safeAreaInsets.top > 0 && gap > 0
        return ScreenLayout(
            screen: screen,
            hasPhysicalNotch: hasNotch,
            notchWidth: hasNotch ? gap : 172,
            notchHeight: hasNotch ? screen.safeAreaInsets.top : 32
        )
    }

    var restingSize: CGSize {
        if hasPhysicalNotch {
            let scale = max(screen.backingScaleFactor, 1)
            let pixelAlignedWidth = (notchWidth * scale).rounded() / scale
            return CGSize(width: pixelAlignedWidth, height: notchHeight + 12)
        }
        return CGSize(width: 190, height: 44)
    }

    var activitySize: CGSize {
        CGSize(width: max(notchWidth + 170, 360), height: max(notchHeight + 50, 78))
    }

    var musicSize: CGSize {
        CGSize(
            width: min(max(notchWidth + 215, 400), 430),
            height: max(notchHeight + 92, 124)
        )
    }

    var launcherSize: CGSize {
        CGSize(
            width: min(max(notchWidth + 310, 500), 560),
            height: max(notchHeight + 86, 118)
        )
    }

    var expandedSize: CGSize {
        let width = min(max(screen.visibleFrame.width * 0.46, 680), 740)
        let height = min(max(screen.visibleFrame.height * 0.50, 470), 520)
        return CGSize(width: width, height: height)
    }

    func size(for presentation: IslandPresentation) -> CGSize {
        switch presentation {
        case .hidden, .compactFocus:
            return restingSize
        case .compactMedia:
            return musicSize
        case .activity:
            return activitySize
        case .music:
            return musicSize
        case .launcher:
            return launcherSize
        case .dashboard:
            return expandedSize
        }
    }

    func frame(for size: CGSize) -> NSRect {
        let topInset: CGFloat = hasPhysicalNotch ? 0 : 7
        return NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height - topInset,
            width: size.width,
            height: size.height
        )
    }
}

final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class NotchPanelController {
    let panel: IslandPanel
    private let state: AppState
    private var layout: ScreenLayout
    private var observers: [NSObjectProtocol] = []
    private var eventMonitor: Any?
    private var hoverTimer: Timer?
    private var pointerWasInside = false
    private var cancellables: Set<AnyCancellable> = []

    init?(state: AppState) {
        guard let layout = ScreenLayout.preferred() else { return nil }
        self.state = state
        self.layout = layout

        let initialSize = layout.size(for: state.presentation)
        let initialFrame = layout.frame(for: initialSize)
        panel = IslandPanel(
            contentRect: initialFrame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.animationBehavior = .none
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.acceptsMouseMovedEvents = true
        panel.contentView = NSHostingView(rootView: IslandRootView(
            state: state,
            hasPhysicalNotch: layout.hasPhysicalNotch,
            notchWidth: layout.notchWidth,
            notchHeight: layout.notchHeight
        ))

        state.onLayoutChanged = { [weak self] in
            self?.syncMouseInteraction()
            self?.updateFrame(animated: true)
        }
        observeFeatureState()
        observeSystemChanges()
        installEscapeHandler()
        installHoverTracking()
        syncMouseInteraction()
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        hoverTimer?.invalidate()
    }

    func show() {
        panel.orderFrontRegardless()
    }

    func toggle() {
        state.toggleExpanded()
        panel.orderFrontRegardless()
        if state.isExpanded { panel.makeKey() }
    }

    func showTools() {
        state.expand(tab: .tools)
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func updateFrame(animated: Bool) {
        guard let latest = ScreenLayout.preferred() else { return }
        let screenChanged = latest.screen != layout.screen || latest.hasPhysicalNotch != layout.hasPhysicalNotch
        layout = latest
        if screenChanged {
            panel.contentView = NSHostingView(rootView: IslandRootView(
                state: state,
                hasPhysicalNotch: layout.hasPhysicalNotch,
                notchWidth: layout.notchWidth,
                notchHeight: layout.notchHeight
            ))
        }

        let size = layout.size(for: state.presentation)
        let target = layout.frame(for: size)

        if framesAreEqual(panel.frame, target) {
            return
        }

        guard animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.setFrame(target, display: true)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.44
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0, 0.2, 1)
            panel.animator().setFrame(target, display: true)
        }
    }

    private func observeFeatureState() {
        state.media.$track
            .map(\.hasContent)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateFrame(animated: true) }
            .store(in: &cancellables)

        state.focus.$isRunning
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateFrame(animated: true) }
            .store(in: &cancellables)
    }

    private func installHoverTracking() {
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.trackPointer() }
        }
        timer.tolerance = 0.004
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer
    }

    private func trackPointer() {
        guard panel.isVisible else { return }
        let point = NSEvent.mouseLocation

        if state.presentation.isHoverSurface {
            let inside = panel.frame.insetBy(dx: -14, dy: -12).contains(point)
            if inside {
                if !pointerWasInside { pointerWasInside = true }
                state.cancelCollapse()
            } else if pointerWasInside {
                pointerWasInside = false
                state.pointerExited()
            }
            return
        }

        let activationFrame = layout.frame(for: layout.restingSize).insetBy(dx: -6, dy: -5)
        let inside = activationFrame.contains(point)
        if inside, !pointerWasInside {
            pointerWasInside = true
            state.pointerEntered()
        } else if !inside {
            pointerWasInside = false
        }
    }

    private func syncMouseInteraction() {
        panel.ignoresMouseEvents = !state.presentation.isHoverSurface
    }

    private func framesAreEqual(_ lhs: NSRect, _ rhs: NSRect) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) < 0.5
            && abs(lhs.origin.y - rhs.origin.y) < 0.5
            && abs(lhs.size.width - rhs.size.width) < 0.5
            && abs(lhs.size.height - rhs.size.height) < 0.5
    }

    private func observeSystemChanges() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.updateFrame(animated: false) } })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateFrame(animated: false)
                self?.show()
            }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.panel.orderOut(nil) })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.show() } })
    }

    private func installEscapeHandler() {
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, let self, self.state.isExpanded else { return event }
            self.state.collapseForced()
            return nil
        }
    }
}
