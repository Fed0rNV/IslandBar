import SwiftUI

struct DashboardView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var media: MediaService
    @ObservedObject private var network: NetworkMonitor
    @ObservedObject private var battery: BatteryService
    @ObservedObject private var calendar: CalendarService
    @ObservedObject private var focus: FocusEngine

    init(state: AppState) {
        self.state = state
        _media = ObservedObject(wrappedValue: state.media)
        _network = ObservedObject(wrappedValue: state.network)
        _battery = ObservedObject(wrappedValue: state.battery)
        _calendar = ObservedObject(wrappedValue: state.calendar)
        _focus = ObservedObject(wrappedValue: state.focus)
    }

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 14) {
                MediaCard(service: media)
                    .frame(width: proxy.size.width * 0.55)

                VStack(spacing: 12) {
                    StatusCard(network: network, battery: battery)
                    NextItemCard(calendar: calendar) {
                        state.selectedTab = .day
                    }
                    QuickFocusCard(engine: focus) {
                        state.selectedTab = .focus
                    }
                }
            }
        }
    }
}

private struct MediaCard: View {
    @ObservedObject var service: MediaService
    @State private var seekValue = 0.0
    @State private var isSeeking = false

    private var primary: Color { Color(nsColor: service.accentColor) }
    private var secondary: Color { Color(nsColor: service.secondaryAccentColor) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(service.track.source.rawValue.isEmpty ? "Сейчас играет" : service.track.source.rawValue,
                      systemImage: service.track.source == .spotify ? "dot.radiowaves.left.and.right" : "music.note")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(IslandPalette.secondary)
                Spacer()
                WaveBars(
                    active: service.track.isPlaying,
                    color: primary,
                    secondaryColor: secondary,
                    barCount: 5
                )
            }

            HStack(spacing: 16) {
                MediaArtworkView(
                    image: service.artwork,
                    primary: primary,
                    secondary: secondary,
                    cornerRadius: 18
                )
                .frame(width: 112, height: 112)
                .animation(.easeInOut(duration: 0.36), value: service.artworkIdentity)
                .animation(.easeInOut(duration: 0.32), value: service.artwork != nil)

                VStack(alignment: .leading, spacing: 6) {
                    Text(service.track.title)
                        .font(.system(size: 19, weight: .bold))
                        .lineLimit(2)
                    Text(service.track.artist)
                        .font(.subheadline)
                        .foregroundStyle(IslandPalette.secondary)
                        .lineLimit(1)
                    if !service.track.album.isEmpty {
                        Text(service.track.album)
                            .font(.caption)
                            .foregroundStyle(Color.white.opacity(0.42))
                            .lineLimit(1)
                    }
                }
            }

            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !service.track.isPlaying)) { timeline in
                let liveProgress = service.track.duration > 0
                    ? service.track.position(at: timeline.date) / service.track.duration
                    : 0
                VStack(spacing: 5) {
                    Slider(
                        value: Binding(
                            get: { isSeeking ? seekValue : liveProgress },
                            set: { seekValue = $0 }
                        ),
                        in: 0...1,
                        onEditingChanged: { editing in
                            isSeeking = editing
                            if !editing { service.seek(progress: seekValue) }
                        }
                    )
                    .tint(primary)
                    .disabled(service.track.duration <= 0)

                    HStack {
                        Text((service.track.duration * (isSeeking ? seekValue : liveProgress)).clockString)
                        Spacer()
                        Text(service.track.duration.clockString)
                    }
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(IslandPalette.secondary)
                }
            }

            HStack(spacing: 20) {
                Spacer()
                Button(action: service.previous) {
                    Image(systemName: "backward.fill")
                }
                .buttonStyle(RoundIconButtonStyle(size: 38))

                Button(action: service.playPause) {
                    Image(systemName: service.track.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 17, weight: .bold))
                }
                .buttonStyle(RoundIconButtonStyle(size: 48))

                Button(action: service.next) {
                    Image(systemName: "forward.fill")
                }
                .buttonStyle(RoundIconButtonStyle(size: 38))
                Spacer()
            }

            if service.automationDenied {
                Label("Разрешите управление Music/Spotify в Системных настройках → Конфиденциальность → Автоматизация.", systemImage: "lock.trianglebadge.exclamationmark")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .islandCard(padding: 17, cornerRadius: 23)
    }
}

private struct StatusCard: View {
    @ObservedObject var network: NetworkMonitor
    @ObservedObject var battery: BatteryService

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Label(network.downloadRate.transferRateString, systemImage: "arrow.down")
                        .foregroundStyle(IslandPalette.mint)
                    Label(network.uploadRate.transferRateString, systemImage: "arrow.up")
                        .foregroundStyle(IslandPalette.accent)
                }
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: battery.symbol)
                        Text(battery.level.map { "\($0)%" } ?? "—")
                    }
                    if let rssi = network.wifiRSSI {
                        Label("\(rssi) dBm", systemImage: "wifi")
                            .foregroundStyle(IslandPalette.secondary)
                    }
                }
                .font(.system(size: 11, weight: .semibold))
            }
            ZStack {
                Sparkline(values: network.downloadHistory, color: IslandPalette.mint)
                Sparkline(values: network.uploadHistory, color: IslandPalette.accent)
            }
            .frame(height: 30)
        }
        .islandCard(padding: 12, cornerRadius: 16)
    }
}

private struct NextItemCard: View {
    @ObservedObject var calendar: CalendarService
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: "calendar")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(IslandPalette.purple)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(IslandPalette.purple.opacity(0.15)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(calendar.events.first?.title ?? "План на день")
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text(nextDetail)
                        .font(.caption2)
                        .foregroundStyle(IslandPalette.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(IslandPalette.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .islandCard(padding: 11, cornerRadius: 16)
    }

    private var nextDetail: String {
        if let event = calendar.events.first {
            return event.isAllDay ? "Весь день" : event.startDate.formatted(date: .abbreviated, time: .shortened)
        }
        switch calendar.accessState {
        case .granted: return "Ближайших событий нет"
        case .loading: return "Загрузка…"
        default: return "Нажмите, чтобы подключить календарь"
        }
    }
}

private struct QuickFocusCard: View {
    @ObservedObject var engine: FocusEngine
    let action: () -> Void

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.1), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: max(engine.progress, 0.02))
                    .stroke(IslandPalette.mint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "timer")
                    .font(.caption.bold())
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(engine.isRunning ? engine.displayTime.clockString : "Быстрый фокус")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(engine.isRunning ? engine.mode.title : "Pomodoro 25 минут")
                    .font(.caption2)
                    .foregroundStyle(IslandPalette.secondary)
            }
            Spacer()
            Button {
                if !engine.isRunning && engine.mode != .pomodoro { engine.select(.pomodoro) }
                engine.startPause()
            } label: {
                Image(systemName: engine.isRunning ? "pause.fill" : "play.fill")
            }
            .buttonStyle(RoundIconButtonStyle(size: 30))
            Button(action: action) {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)
        }
        .islandCard(padding: 11, cornerRadius: 16)
    }
}
