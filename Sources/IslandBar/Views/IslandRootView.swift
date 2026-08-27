import SwiftUI
import UniformTypeIdentifiers

struct IslandRootView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var media: MediaService
    @ObservedObject private var focus: FocusEngine
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var musicMotion

    let hasPhysicalNotch: Bool
    let notchWidth: CGFloat
    let notchHeight: CGFloat

    init(state: AppState, hasPhysicalNotch: Bool, notchWidth: CGFloat, notchHeight: CGFloat = 32) {
        self.state = state
        self.hasPhysicalNotch = hasPhysicalNotch
        self.notchWidth = notchWidth
        self.notchHeight = notchHeight
        _media = ObservedObject(wrappedValue: state.media)
        _focus = ObservedObject(wrappedValue: state.focus)
    }

    var body: some View {
        GeometryReader { proxy in
            let presentation = state.presentation
            let restingCompact = presentation == .hidden || presentation == .compactFocus
            let mediaCompactWidth = notchWidth + 44
            let surfaceWidth = presentation == .compactMedia
                ? min(mediaCompactWidth, proxy.size.width)
                : (restingCompact ? min(notchWidth, proxy.size.width) : proxy.size.width)
            let surfaceHeight = presentation == .compactMedia
                ? min(notchHeight, proxy.size.height)
                : (restingCompact ? min(notchHeight + 12, proxy.size.height) : proxy.size.height)
            ZStack(alignment: .top) {
                TopAttachedSurfaceShape(
                    bottomRadius: cornerRadius(for: presentation),
                    hasPhysicalNotch: hasPhysicalNotch
                )
                .fill(Color.black)
                .frame(width: surfaceWidth, height: surfaceHeight)
                .opacity(presentation == .hidden ? 0 : 1)

                content(for: presentation)

                if state.isDropTargeted {
                    DropTargetOverlay()
                        .transition(.opacity)
                }
            }
            .animation(
                reduceMotion
                    ? .easeOut(duration: 0.16)
                    : .interactiveSpring(response: 0.40, dampingFraction: 0.92, blendDuration: 0.16),
                value: presentation
            )
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $state.isDropTargeted) { providers in
                loadDroppedURLs(providers)
                return true
            }
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func content(for presentation: IslandPresentation) -> some View {
        switch presentation {
        case .hidden:
            Color.clear
        case .compactMedia:
            CompactMediaView(service: media, namespace: musicMotion)
                .frame(width: notchWidth + 44, height: notchHeight)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        case .compactFocus:
            CompactFocusView(engine: focus)
        case .activity:
            if let activity = state.activity {
                ActivityIslandView(activity: activity, topInset: hasPhysicalNotch ? notchHeight + 6 : 8)
                    .transition(.opacity)
            }
        case .music:
            MusicLiveActivityView(
                state: state,
                service: media,
                notchHeight: notchHeight,
                namespace: musicMotion
            )
        case .launcher:
            QuickLauncherView(
                state: state,
                topInset: hasPhysicalNotch ? notchHeight + 10 : 10
            )
            .transition(.opacity)
        case .dashboard:
            ExpandedIslandView(
                state: state,
                topInset: hasPhysicalNotch ? notchHeight + 18 : 20
            )
            .transition(.opacity)
        }
    }

    private func cornerRadius(for presentation: IslandPresentation) -> CGFloat {
        switch presentation {
        case .hidden, .compactMedia, .compactFocus: return 8
        case .activity: return 17
        case .music, .launcher: return 20
        case .dashboard: return 26
        }
    }

    private func loadDroppedURLs(_ providers: [NSItemProvider]) {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []
        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                let url: URL?
                if let value = item as? URL {
                    url = value
                } else if let value = item as? NSURL {
                    url = value as URL
                } else if let data = item as? Data,
                          let string = String(data: data, encoding: .utf8) {
                    url = URL(string: string.trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    url = nil
                }
                if let url {
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                }
            }
        }
        group.notify(queue: .main) { state.addFiles(urls) }
    }
}

private struct CompactMediaView: View {
    @ObservedObject var service: MediaService
    let namespace: Namespace.ID

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            MediaArtworkView(
                image: service.artwork,
                primary: Color(nsColor: service.accentColor),
                secondary: Color(nsColor: service.secondaryAccentColor),
                cornerRadius: 3.5
            )
            .frame(width: 14, height: 14)
            .matchedGeometryEffect(id: "media-artwork", in: namespace)

            Spacer(minLength: 0)

            WaveBars(
                active: service.track.isPlaying,
                color: Color(nsColor: service.accentColor),
                secondaryColor: Color(nsColor: service.secondaryAccentColor),
                barCount: 4,
                barWidth: 2,
                maximumHeight: 12
            )
        }
        .padding(.horizontal, 4)
        .frame(height: 14, alignment: .center)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .animation(.easeInOut(duration: 0.36), value: service.artworkIdentity)
        .animation(.easeInOut(duration: 0.32), value: service.artwork != nil)
    }
}

private struct CompactFocusView: View {
    @ObservedObject var engine: FocusEngine

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "timer")
                .foregroundStyle(IslandPalette.mint)
            Text(engine.displayTime.clockString)
                .monospacedDigit()
        }
        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
        .padding(.horizontal, 9)
        .frame(height: 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}

private struct ActivityIslandView: View {
    let activity: QuickActivity
    let topInset: CGFloat

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: activity.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(IslandPalette.mint)
                .frame(width: 29, height: 29)
                .background(Circle().fill(IslandPalette.mint.opacity(0.14)))
            VStack(alignment: .leading, spacing: 1) {
                Text(activity.title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .lineLimit(1)
                Text(activity.detail)
                    .font(.system(size: 9.5))
                    .foregroundStyle(IslandPalette.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, topInset)
        .padding(.bottom, 9)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MusicLiveActivityView: View {
    @ObservedObject var state: AppState
    @ObservedObject var service: MediaService
    let notchHeight: CGFloat
    let namespace: Namespace.ID

    private var primary: Color { Color(nsColor: service.accentColor) }
    private var secondary: Color { Color(nsColor: service.secondaryAccentColor) }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: notchHeight + 8)
                .allowsHitTesting(false)

            HStack(spacing: 0) {
                MediaArtworkView(
                    image: service.artwork,
                    primary: primary,
                    secondary: secondary,
                    cornerRadius: 11
                )
                .frame(width: 64, height: 64)
                .matchedGeometryEffect(id: "media-artwork", in: namespace)

                VStack(alignment: .leading, spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(service.track.title)
                            .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                        Text(service.track.artist)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(IslandPalette.secondary)
                            .lineLimit(1)
                    }

                    MusicProgressAndControls(service: service, tint: primary)
                }
                .padding(.leading, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)

                ZStack(alignment: .bottom) {
                    WaveBars(
                        active: service.track.isPlaying,
                        color: primary,
                        secondaryColor: secondary,
                        barCount: 4,
                        barWidth: 2.8,
                        maximumHeight: 22
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .transition(.opacity.combined(with: .scale(scale: 0.82)))

                    Button { state.expand(tab: .home) } label: {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 9, weight: .semibold))
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.white.opacity(0.09)))
                    }
                    .buttonStyle(.plain)
                    .help("Открыть все возможности")
                }
                .frame(width: 32, height: 72)
                .padding(.leading, 12)
            }
            .frame(height: 72)
            .padding(.horizontal, 16)

            Color.clear
                .frame(height: 12)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.36), value: service.artworkIdentity)
        .animation(.easeInOut(duration: 0.32), value: service.artwork != nil)
    }
}

private struct MusicProgressAndControls: View {
    @ObservedObject var service: MediaService
    let tint: Color
    @State private var draggedProgress: Double?

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !service.track.isPlaying)) { timeline in
            let livePosition = service.track.position(at: timeline.date)
            let liveProgress = service.track.duration > 0 ? livePosition / service.track.duration : 0
            let shownProgress = draggedProgress ?? liveProgress
            let shownPosition = service.track.duration * shownProgress

            VStack(spacing: 5) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.16))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [tint.opacity(0.72), tint],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(proxy.size.width * shownProgress, 0))
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                draggedProgress = min(max(value.location.x / max(proxy.size.width, 1), 0), 1)
                            }
                            .onEnded { value in
                                let progress = min(max(value.location.x / max(proxy.size.width, 1), 0), 1)
                                service.seek(progress: progress)
                                draggedProgress = nil
                            }
                    )
                }
                .frame(height: 3.5)

                HStack(spacing: 8) {
                    Text(shownPosition.clockString)
                        .frame(width: 31, alignment: .leading)

                    Spacer(minLength: 0)

                    Button(action: service.previous) {
                        Image(systemName: "backward.fill")
                    }
                    .buttonStyle(MusicTransportButtonStyle(size: 22))

                    Button(action: service.playPause) {
                        Image(systemName: service.track.isPlaying ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(MusicTransportButtonStyle(size: 26))

                    Button(action: service.next) {
                        Image(systemName: "forward.fill")
                    }
                    .buttonStyle(MusicTransportButtonStyle(size: 22))

                    Spacer(minLength: 0)

                    Text("−\(max(service.track.duration - shownPosition, 0).clockString)")
                        .frame(width: 37, alignment: .trailing)
                }
                .font(.system(size: 8.5, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.72))
                .monospacedDigit()
            }
        }
    }
}

private struct MusicTransportButtonStyle: ButtonStyle {
    let size: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.43, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .scaleEffect(configuration.isPressed ? 0.84 : 1)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct QuickLauncherView: View {
    @ObservedObject var state: AppState
    let topInset: CGFloat

    private let tabs: [IslandTab] = [.shelf, .clipboard, .focus, .day, .tools, .browser]

    var body: some View {
        HStack(spacing: 10) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.date.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(context.date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(IslandPalette.secondary)
                        .lineLimit(1)
                }
                .frame(width: 112, alignment: .leading)
            }

            Rectangle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 1, height: 38)

            ForEach(tabs) { tab in
                Button {
                    state.expand(tab: tab)
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(Color.white.opacity(0.09)))
                        Text(tab.title)
                            .font(.system(size: 8.5, weight: .medium))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 17)
        .padding(.top, topInset)
        .padding(.bottom, 11)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DropTargetOverlay: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(IslandPalette.accent.opacity(0.2))
            VStack(spacing: 7) {
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.system(size: 30, weight: .semibold))
                Text("Отпустите — файлы попадут на полку")
                    .font(.headline)
            }
        }
        .padding(8)
        .allowsHitTesting(false)
    }
}

private struct ExpandedIslandView: View {
    @ObservedObject var state: AppState
    let topInset: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 22)

            tabBar
                .padding(.horizontal, 20)
                .padding(.top, 10)

            ZStack {
                switch state.selectedTab {
                case .home: DashboardView(state: state)
                case .shelf: ShelfView(state: state)
                case .clipboard: ClipboardView(monitor: state.clipboard)
                case .focus: FocusView(engine: state.focus)
                case .day: DayView(service: state.calendar)
                case .tools: ToolsView(state: state)
                case .browser: BrowserView()
                }
            }
            .id(state.selectedTab)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.16), value: state.selectedTab)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 18)
        }
        .padding(.top, topInset)
    }

    private var header: some View {
        HStack(spacing: 12) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Text(context.date.formatted(date: .omitted, time: .shortened))
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(context.date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(.caption)
                        .foregroundStyle(IslandPalette.secondary)
                }
            }
            Spacer()
            Button { state.isPinned.toggle() } label: {
                Image(systemName: state.isPinned ? "pin.fill" : "pin")
            }
            .buttonStyle(RoundIconButtonStyle(size: 29))
            .help(state.isPinned ? "Открепить" : "Не сворачивать")

            Button { state.collapseForced() } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(RoundIconButtonStyle(size: 29))
            .help("Свернуть (Esc)")
        }
    }

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(IslandTab.allCases) { tab in
                Button {
                    state.selectedTab = tab
                    if tab != .tools { state.camera.stop() }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.symbol)
                        if state.selectedTab == tab { Text(tab.title) }
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, state.selectedTab == tab ? 10 : 8)
                    .frame(height: 29)
                    .background(
                        Capsule().fill(state.selectedTab == tab ? Color.white.opacity(0.14) : .clear)
                    )
                    .foregroundStyle(state.selectedTab == tab ? Color.white : IslandPalette.secondary)
                }
                .buttonStyle(.plain)
                .help(tab.title)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(4)
        .background(Capsule().fill(Color.white.opacity(0.055)))
    }
}
