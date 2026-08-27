import AppKit
import ServiceManagement
import SwiftUI
import WebKit

private enum ToolsSection: String, CaseIterable, Identifiable {
    case apps
    case notes
    case trackers
    case camera
    case settings

    var id: String { rawValue }
    var title: String {
        switch self {
        case .apps: return "Приложения"
        case .notes: return "Заметки"
        case .trackers: return "Счётчики"
        case .camera: return "Зеркало"
        case .settings: return "Настройки"
        }
    }
    var symbol: String {
        switch self {
        case .apps: return "square.grid.3x3"
        case .notes: return "note.text"
        case .trackers: return "chart.bar.fill"
        case .camera: return "camera.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

struct ToolsView: View {
    @ObservedObject var state: AppState
    @ObservedObject private var camera: CameraService
    @State private var section: ToolsSection = .apps

    init(state: AppState) {
        self.state = state
        _camera = ObservedObject(wrappedValue: state.camera)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 5) {
                ForEach(ToolsSection.allCases) { item in
                    Button {
                        section = item
                        if item == .camera { camera.start() } else { camera.stop() }
                    } label: {
                        Label(item.title, systemImage: item.symbol)
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 11)
                            .frame(height: 29)
                            .background(Capsule().fill(section == item ? Color.white.opacity(0.14) : .clear))
                            .foregroundStyle(section == item ? Color.white : IslandPalette.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Group {
                switch section {
                case .apps: AppShortcutsView(state: state)
                case .notes: NotesLinksView(state: state)
                case .trackers: TrackersView(state: state)
                case .camera: CameraMirrorView(service: camera)
                case .settings: SettingsView(state: state)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onDisappear { camera.stop() }
    }
}

private struct AppShortcutsView: View {
    @ObservedObject var state: AppState
    private let columns = [GridItem(.adaptive(minimum: 88, maximum: 120), spacing: 12)]

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Быстрый запуск")
                        .font(.headline)
                    Text("Добавьте любые приложения с этого Mac")
                        .font(.caption)
                        .foregroundStyle(IslandPalette.secondary)
                }
                Spacer()
                Button(action: state.chooseShortcut) {
                    Label("Добавить", systemImage: "plus")
                }
                .buttonStyle(IslandButtonStyle(tint: IslandPalette.accent.opacity(0.55)))
            }

            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(state.shortcuts) { shortcut in
                        Button {
                            state.launch(shortcut)
                        } label: {
                            VStack(spacing: 8) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: shortcut.path))
                                    .resizable()
                                    .frame(width: 44, height: 44)
                                Text(shortcut.name)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, minHeight: 82)
                            .islandCard(padding: 9, cornerRadius: 16)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Убрать ярлык", action: { state.removeShortcut(shortcut) })
                        }
                    }
                    Button(action: state.chooseShortcut) {
                        VStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.system(size: 22, weight: .medium))
                                .frame(width: 44, height: 44)
                                .background(Circle().fill(Color.white.opacity(0.08)))
                            Text("Добавить")
                                .font(.caption.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity, minHeight: 82)
                        .islandCard(padding: 9, cornerRadius: 16)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct NotesLinksView: View {
    @ObservedObject var state: AppState
    @State private var linkTitle = ""
    @State private var linkAddress = ""

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Быстрая заметка", systemImage: "note.text")
                    .font(.headline)
                TextEditor(text: $state.quickNote)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 13).fill(Color.white.opacity(0.055)))
                Text("Сохраняется автоматически только на этом Mac")
                    .font(.caption2)
                    .foregroundStyle(IslandPalette.secondary)
            }
            .frame(maxWidth: .infinity)
            .islandCard(padding: 13, cornerRadius: 18)

            VStack(alignment: .leading, spacing: 8) {
                Label("Закладки", systemImage: "bookmark.fill")
                    .font(.headline)

                HStack(spacing: 6) {
                    TextField("Название", text: $linkTitle)
                    TextField("Ссылка", text: $linkAddress)
                        .onSubmit(addLink)
                    Button(action: addLink) { Image(systemName: "plus") }
                        .buttonStyle(RoundIconButtonStyle(size: 29))
                }
                .textFieldStyle(.plain)
                .padding(.horizontal, 9)
                .frame(height: 31)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.07)))

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 7) {
                        if state.savedLinks.isEmpty {
                            Text("Добавьте ссылку — она появится здесь")
                                .font(.caption)
                                .foregroundStyle(IslandPalette.secondary)
                                .frame(maxWidth: .infinity, minHeight: 90)
                        }
                        ForEach(state.savedLinks) { link in
                            HStack(spacing: 9) {
                                Image(systemName: "link")
                                    .foregroundStyle(IslandPalette.accent)
                                Text(link.title)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                                Spacer()
                                Button { state.open(link) } label: { Image(systemName: "arrow.up.right") }
                                    .buttonStyle(.plain)
                                Button { state.removeLink(link) } label: { Image(systemName: "xmark") }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(IslandPalette.secondary)
                            }
                            .padding(9)
                            .background(RoundedRectangle(cornerRadius: 11).fill(Color.white.opacity(0.05)))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .islandCard(padding: 13, cornerRadius: 18)
        }
    }

    private func addLink() {
        state.addLink(title: linkTitle, address: linkAddress)
        linkTitle = ""
        linkAddress = ""
    }
}

private struct TrackersView: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 13) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 25))
                    .foregroundStyle(.cyan)
                Text("Вода сегодня")
                    .font(.headline)
                ZStack {
                    Circle().stroke(Color.white.opacity(0.08), lineWidth: 9)
                    Circle()
                        .trim(from: 0, to: min(Double(state.waterCount) / Double(max(state.waterTarget, 1)), 1))
                        .stroke(.cyan, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(state.waterCount)/\(state.waterTarget)")
                        .font(.title2.bold())
                        .monospacedDigit()
                }
                .frame(width: 100, height: 100)
                HStack {
                    Button { state.waterCount = max(state.waterCount - 1, 0) } label: { Image(systemName: "minus") }
                        .buttonStyle(RoundIconButtonStyle())
                    Button(action: state.drinkWater) { Label("Стакан", systemImage: "plus") }
                        .buttonStyle(IslandButtonStyle(tint: .cyan.opacity(0.45)))
                }
                Stepper("Цель: \(state.waterTarget)", value: $state.waterTarget, in: 1...20)
                    .font(.caption)
                    .controlSize(.small)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .islandCard(padding: 14, cornerRadius: 19)

            VStack(spacing: 13) {
                Image(systemName: "number.circle.fill")
                    .font(.system(size: 25))
                    .foregroundStyle(IslandPalette.purple)
                Text("Счётчик")
                    .font(.headline)
                Text("\(state.habitCount)")
                    .font(.system(size: 58, weight: .bold, design: .rounded))
                    .monospacedDigit()
                HStack(spacing: 13) {
                    Button { state.habitCount -= 1 } label: { Image(systemName: "minus") }
                        .buttonStyle(RoundIconButtonStyle(size: 40))
                    Button { state.habitCount = 0 } label: { Image(systemName: "arrow.counterclockwise") }
                        .buttonStyle(RoundIconButtonStyle(size: 40))
                    Button { state.habitCount += 1 } label: { Image(systemName: "plus") }
                        .buttonStyle(RoundIconButtonStyle(size: 40))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .islandCard(padding: 14, cornerRadius: 19)

            VStack(spacing: 12) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 25))
                    .foregroundStyle(IslandPalette.mint)
                TextField("Название", text: $state.daysTitle)
                    .textFieldStyle(.plain)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text("\(abs(state.daysRemaining))")
                    .font(.system(size: 58, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(state.daysRemaining >= 0 ? "дней осталось" : "дней прошло")
                    .font(.caption)
                    .foregroundStyle(IslandPalette.secondary)
                DatePicker("", selection: $state.daysDate, displayedComponents: [.date])
                    .labelsHidden()
                    .controlSize(.small)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .islandCard(padding: 14, cornerRadius: 19)
        }
    }
}

private struct CameraMirrorView: View {
    @ObservedObject var service: CameraService

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.04))
            switch service.state {
            case .ready:
                CameraPreview(session: service.session)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .scaleEffect(x: -1, y: 1)
                    .overlay(alignment: .bottomLeading) {
                        Label("Зеркало — видео никуда не сохраняется", systemImage: "lock.shield")
                            .font(.caption)
                            .padding(10)
                            .background(.black.opacity(0.5), in: Capsule())
                            .padding(12)
                    }
            case .requesting:
                ProgressView("Подключаем камеру…")
            case .denied:
                CameraMessage(
                    symbol: "camera.badge.ellipsis",
                    title: "Нет доступа к камере",
                    detail: "Разрешите IslandBar в Системных настройках → Конфиденциальность и безопасность → Камера"
                )
            case .unavailable:
                CameraMessage(symbol: "video.slash", title: "Камера не найдена", detail: "Подключите камеру и попробуйте снова")
            case .failed(let message):
                CameraMessage(symbol: "exclamationmark.triangle", title: "Не удалось запустить камеру", detail: message)
            case .idle:
                Button(action: service.start) {
                    Label("Включить зеркало", systemImage: "camera.fill")
                }
                .buttonStyle(IslandButtonStyle(tint: IslandPalette.accent.opacity(0.55)))
            }
        }
    }
}

private struct CameraMessage: View {
    let symbol: String
    let title: String
    let detail: String

    var body: some View {
        EmptyStateView(symbol: symbol, title: title, detail: detail)
    }
}

private struct SettingsView: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Поведение островка")
                    .font(.headline)
                SettingToggle(title: "Открывать при наведении", detail: "Достаточно подвести указатель к вырезу", isOn: $state.hoverToOpen)
                SettingToggle(title: "Сворачивать автоматически", detail: "После ухода указателя с небольшой задержкой", isOn: $state.autoCollapse)
                SettingToggle(title: "Следить за буфером", detail: "История хранится только до выхода из приложения", isOn: Binding(
                    get: { state.clipboard.isEnabled },
                    set: { state.clipboard.isEnabled = $0 }
                ))
                SettingToggle(title: "Запускать при входе", detail: "macOS может попросить подтвердить в Login Items", isOn: Binding(
                    get: { state.loginItemEnabled },
                    set: { _ in state.toggleLoginItem() }
                ))
                Button {
                    SMAppService.openSystemSettingsLoginItems()
                } label: {
                    Label("Открыть объекты входа", systemImage: "gear")
                }
                .buttonStyle(IslandButtonStyle())
            }
            .frame(maxWidth: .infinity)
            .islandCard(padding: 15, cornerRadius: 19)

            VStack(alignment: .leading, spacing: 12) {
                Text("Приватность и сведения")
                    .font(.headline)
                Label("Без аккаунта и облака", systemImage: "checkmark.icloud")
                Label("Файлы не копируются", systemImage: "externaldrive")
                Label("Буфер не пишется на диск", systemImage: "memorychip")
                Label("Камера используется только для зеркала", systemImage: "camera")
                Divider().overlay(Color.white.opacity(0.1))
                Text("IslandBar " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""))
                    .font(.subheadline.weight(.semibold))
                Text("Оригинальное локальное приложение в стиле Dynamic Island. Не связано с NotchBox или Apple.")
                    .font(.caption)
                    .foregroundStyle(IslandPalette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button {
                    state.showActivity(symbol: "hand.thumbsup.fill", title: "IslandBar работает локально", detail: "Нет собственного сервера и телеметрии")
                } label: {
                    Label("Проверка островка", systemImage: "sparkles")
                }
                .buttonStyle(IslandButtonStyle(tint: IslandPalette.purple.opacity(0.45)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .islandCard(padding: 15, cornerRadius: 19)
        }
        .font(.subheadline)
    }
}

private struct SettingToggle: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption2).foregroundStyle(IslandPalette.secondary)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

@MainActor
final class BrowserModel: NSObject, ObservableObject, WKNavigationDelegate {
    @Published var address = ""
    @Published private(set) var isLoading = false
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false

    let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())

    override init() {
        super.init()
        webView.navigationDelegate = self
        webView.allowsMagnification = true
        goHome()
    }

    func go() {
        navigate(address)
    }

    func goHome() {
        navigate("https://www.google.com")
    }

    func back() { webView.goBack(); refreshState() }
    func forward() { webView.goForward(); refreshState() }
    func reload() { webView.reload() }

    func openExternal() {
        if let url = webView.url { NSWorkspace.shared.open(url) }
    }

    func navigate(_ input: String) {
        let clean = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        let url: URL?
        if let direct = URL(string: clean), direct.scheme != nil {
            url = direct
        } else if clean.contains(".") && !clean.contains(" ") {
            url = URL(string: "https://\(clean)")
        } else {
            var components = URLComponents(string: "https://www.google.com/search")
            components?.queryItems = [URLQueryItem(name: "q", value: clean)]
            url = components?.url
        }
        guard let url else { return }
        address = url.absoluteString
        webView.load(URLRequest(url: url))
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
        refreshState()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        address = webView.url?.absoluteString ?? address
        refreshState()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        refreshState()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        refreshState()
    }

    private func refreshState() {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }
}

struct BrowserView: View {
    @StateObject private var model = BrowserModel()

    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 7) {
                Button(action: model.back) { Image(systemName: "chevron.left") }
                    .buttonStyle(RoundIconButtonStyle(size: 30))
                    .disabled(!model.canGoBack)
                Button(action: model.forward) { Image(systemName: "chevron.right") }
                    .buttonStyle(RoundIconButtonStyle(size: 30))
                    .disabled(!model.canGoForward)
                Button(action: model.reload) {
                    Image(systemName: model.isLoading ? "xmark" : "arrow.clockwise")
                }
                .buttonStyle(RoundIconButtonStyle(size: 30))

                HStack(spacing: 7) {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(IslandPalette.mint)
                    TextField("Адрес или запрос", text: $model.address)
                        .textFieldStyle(.plain)
                        .onSubmit(model.go)
                }
                .padding(.horizontal, 10)
                .frame(height: 31)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.075)))

                Button(action: model.openExternal) { Image(systemName: "safari") }
                    .buttonStyle(RoundIconButtonStyle(size: 30))
                    .help("Открыть во внешнем браузере")
            }

            BrowserWebView(webView: model.webView)
                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .stroke(IslandPalette.stroke, lineWidth: 1)
                )
        }
    }
}

private struct BrowserWebView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) { }
}
