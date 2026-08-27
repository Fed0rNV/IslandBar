import AppKit
import Combine
import Foundation
import ServiceManagement
import UniformTypeIdentifiers

@MainActor
final class AppState: ObservableObject {
    let clipboard = ClipboardMonitor()
    let calendar = CalendarService()
    let network = NetworkMonitor()
    let battery = BatteryService()
    let media = MediaService()
    let focus = FocusEngine()
    let camera = CameraService()

    @Published var isExpanded = false {
        didSet { if oldValue != isExpanded { onLayoutChanged?() } }
    }
    @Published private(set) var isHoverPresented = false {
        didSet { if oldValue != isHoverPresented { onLayoutChanged?() } }
    }
    @Published var isPinned = false { didSet { defaults.set(isPinned, forKey: Keys.pinned) } }
    @Published var selectedTab: IslandTab = .home
    @Published var isDropTargeted = false
    @Published var activity: QuickActivity? {
        didSet { if oldValue != activity { onLayoutChanged?() } }
    }

    @Published var shelfItems: [ShelfItem] = [] { didSet { save(shelfItems, key: Keys.shelf) } }
    @Published var shortcuts: [ShortcutItem] = [] { didSet { save(shortcuts, key: Keys.shortcuts) } }
    @Published var savedLinks: [SavedLink] = [] { didSet { save(savedLinks, key: Keys.links) } }
    @Published var quickNote = "" { didSet { defaults.set(quickNote, forKey: Keys.note) } }
    @Published var waterCount = 0 { didSet { defaults.set(waterCount, forKey: Keys.water) } }
    @Published var waterTarget = 8 { didSet { defaults.set(waterTarget, forKey: Keys.waterTarget) } }
    @Published var habitCount = 0 { didSet { defaults.set(habitCount, forKey: Keys.habit) } }
    @Published var daysTitle = "Важная дата" { didSet { defaults.set(daysTitle, forKey: Keys.daysTitle) } }
    @Published var daysDate = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date() {
        didSet { defaults.set(daysDate, forKey: Keys.daysDate) }
    }
    @Published var hoverToOpen = true { didSet { defaults.set(hoverToOpen, forKey: Keys.hover) } }
    @Published var autoCollapse = true { didSet { defaults.set(autoCollapse, forKey: Keys.autoCollapse) } }
    @Published private(set) var loginItemEnabled = false

    var onLayoutChanged: (() -> Void)?
    var onRequestSettings: (() -> Void)?
    var keepExpandedForTesting = false

    private let defaults = UserDefaults.standard
    private var collapseWorkItem: DispatchWorkItem?
    private var activityWorkItem: DispatchWorkItem?

    private enum Keys {
        static let shelf = "islandbar.shelf"
        static let shortcuts = "islandbar.shortcuts"
        static let links = "islandbar.links"
        static let note = "islandbar.note"
        static let water = "islandbar.water"
        static let waterTarget = "islandbar.waterTarget"
        static let waterDate = "islandbar.waterDate"
        static let habit = "islandbar.habit"
        static let daysTitle = "islandbar.daysTitle"
        static let daysDate = "islandbar.daysDate"
        static let pinned = "islandbar.pinned"
        static let hover = "islandbar.hover"
        static let autoCollapse = "islandbar.autoCollapse"
    }

    init() {
        shelfItems = load([ShelfItem].self, key: Keys.shelf) ?? []
        shortcuts = load([ShortcutItem].self, key: Keys.shortcuts) ?? Self.defaultShortcuts()
        savedLinks = load([SavedLink].self, key: Keys.links) ?? []
        quickNote = defaults.string(forKey: Keys.note) ?? ""
        waterCount = defaults.integer(forKey: Keys.water)
        waterTarget = defaults.object(forKey: Keys.waterTarget) == nil ? 8 : defaults.integer(forKey: Keys.waterTarget)
        habitCount = defaults.integer(forKey: Keys.habit)
        daysTitle = defaults.string(forKey: Keys.daysTitle) ?? "Важная дата"
        daysDate = defaults.object(forKey: Keys.daysDate) as? Date
            ?? Calendar.current.date(byAdding: .day, value: 30, to: Date())
            ?? Date()
        isPinned = defaults.bool(forKey: Keys.pinned)
        hoverToOpen = defaults.object(forKey: Keys.hover) == nil ? true : defaults.bool(forKey: Keys.hover)
        autoCollapse = defaults.object(forKey: Keys.autoCollapse) == nil ? true : defaults.bool(forKey: Keys.autoCollapse)

        resetWaterIfNeeded()
        refreshLoginItemStatus()
        focus.onCompleted = { [weak self] title, detail in
            self?.showActivity(symbol: "timer", title: title, detail: detail, duration: 5)
        }
    }

    var daysRemaining: Int {
        let start = Calendar.current.startOfDay(for: Date())
        let target = Calendar.current.startOfDay(for: daysDate)
        return Calendar.current.dateComponents([.day], from: start, to: target).day ?? 0
    }

    var presentation: IslandPresentation {
        if isExpanded { return .dashboard }
        if isHoverPresented {
            return media.track.hasContent ? .music : .launcher
        }
        if activity != nil { return .activity }
        if media.track.hasContent { return .compactMedia }
        if focus.isRunning { return .compactFocus }
        return .hidden
    }

    func expand(tab: IslandTab? = nil) {
        cancelCollapse()
        if let tab { selectedTab = tab }
        guard !isExpanded else { return }
        isExpanded = true
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    func collapse() {
        guard !isPinned, !keepExpandedForTesting else { return }
        if isHoverPresented { isHoverPresented = false }
        if isExpanded { isExpanded = false }
        camera.stop()
    }

    func toggleExpanded() {
        isExpanded ? collapseForced() : expand()
    }

    func collapseForced() {
        isPinned = false
        if isHoverPresented { isHoverPresented = false }
        if isExpanded { isExpanded = false }
        camera.stop()
    }

    func pointerEntered() {
        cancelCollapse()
        guard hoverToOpen, !isExpanded, !isHoverPresented else { return }
        isHoverPresented = true
    }

    func pointerExited() {
        guard autoCollapse, !isPinned else { return }
        scheduleCollapse()
    }

    func presentHoverForTesting() {
        cancelCollapse()
        isHoverPresented = true
    }

    func scheduleCollapse(after delay: TimeInterval = 0.55) {
        cancelCollapse()
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.collapse() }
        }
        collapseWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    func cancelCollapse() {
        collapseWorkItem?.cancel()
        collapseWorkItem = nil
    }

    func addFiles(_ urls: [URL]) {
        let clean = urls.filter { url in
            !shelfItems.contains(where: { $0.path == url.path })
        }
        guard !clean.isEmpty else { return }
        shelfItems.append(contentsOf: clean.map(ShelfItem.init(url:)))
        selectedTab = .shelf
        expand()
        isDropTargeted = false
        showActivity(symbol: "tray.and.arrow.down.fill", title: "Добавлено файлов: \(clean.count)", detail: "Они останутся на полке после перезапуска")
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.title = "Добавить на полку"
        panel.prompt = "Добавить"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { addFiles(panel.urls) }
    }

    func removeShelfItem(_ item: ShelfItem) {
        shelfItems.removeAll { $0.id == item.id }
    }

    func clearShelf() {
        shelfItems.removeAll()
    }

    func open(_ item: ShelfItem) {
        NSWorkspace.shared.open(item.url)
    }

    func reveal(_ item: ShelfItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func shareByAirDrop(_ items: [ShelfItem]) {
        let urls = items.filter(\.exists).map(\.url)
        guard !urls.isEmpty else { return }
        guard let service = NSSharingService(named: .sendViaAirDrop) else {
            showActivity(symbol: "exclamationmark.triangle", title: "AirDrop недоступен", detail: "Проверьте Wi‑Fi и Bluetooth")
            return
        }
        service.perform(withItems: urls)
    }

    func chooseShortcut() {
        let panel = NSOpenPanel()
        panel.title = "Добавить приложение"
        panel.prompt = "Добавить"
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        if panel.runModal() == .OK, let url = panel.url {
            shortcuts.append(ShortcutItem(name: url.deletingPathExtension().lastPathComponent, path: url.path))
        }
    }

    func launch(_ shortcut: ShortcutItem) {
        NSWorkspace.shared.openApplication(at: shortcut.url, configuration: .init()) { _, error in
            if let error {
                Task { @MainActor in
                    self.showActivity(symbol: "exclamationmark.triangle", title: "Не удалось открыть", detail: error.localizedDescription)
                }
            }
        }
    }

    func removeShortcut(_ shortcut: ShortcutItem) {
        shortcuts.removeAll { $0.id == shortcut.id }
    }

    func addLink(title: String, address: String) {
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAddress.isEmpty else { return }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        savedLinks.append(SavedLink(title: trimmedTitle.isEmpty ? trimmedAddress : trimmedTitle, address: trimmedAddress))
    }

    func open(_ link: SavedLink) {
        if let url = link.url { NSWorkspace.shared.open(url) }
    }

    func removeLink(_ link: SavedLink) {
        savedLinks.removeAll { $0.id == link.id }
    }

    func drinkWater() {
        resetWaterIfNeeded()
        waterCount = min(waterCount + 1, max(waterTarget, 1))
    }

    func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            refreshLoginItemStatus()
        } catch {
            showActivity(symbol: "gear.badge.xmark", title: "Не удалось изменить автозапуск", detail: error.localizedDescription, duration: 5)
        }
    }

    func refreshLoginItemStatus() {
        loginItemEnabled = SMAppService.mainApp.status == .enabled
    }

    func showActivity(symbol: String, title: String, detail: String, duration: TimeInterval = 3.2) {
        activityWorkItem?.cancel()
        activity = QuickActivity(symbol: symbol, title: title, detail: detail)
        let item = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.activity = nil }
        }
        activityWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: item)
    }

    private func resetWaterIfNeeded() {
        let today = Calendar.current.startOfDay(for: Date())
        let stored = defaults.object(forKey: Keys.waterDate) as? Date
        if stored.map({ !Calendar.current.isDate($0, inSameDayAs: today) }) ?? true {
            waterCount = 0
            defaults.set(today, forKey: Keys.waterDate)
        }
    }

    private func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private static func defaultShortcuts() -> [ShortcutItem] {
        [
            ("Finder", "/System/Library/CoreServices/Finder.app"),
            ("Safari", "/Applications/Safari.app"),
            ("Календарь", "/System/Applications/Calendar.app"),
            ("Музыка", "/System/Applications/Music.app")
        ]
        .filter { FileManager.default.fileExists(atPath: $0.1) }
        .map { ShortcutItem(name: $0.0, path: $0.1) }
    }
}
