import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var state: AppState!
    private var panelController: NotchPanelController?
    private var statusItem: NSStatusItem?
    private weak var loginMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        state = AppState()
        if CommandLine.arguments.contains("--expanded") {
            state.isExpanded = true
            state.isPinned = false
            state.keepExpandedForTesting = true
        }
        if CommandLine.arguments.contains("--peek") {
            state.presentHoverForTesting()
        }
        if CommandLine.arguments.contains("--media-preview") {
            state.media.installTestingPreview()
        }
        if let index = CommandLine.arguments.firstIndex(of: "--tab"),
           CommandLine.arguments.indices.contains(index + 1),
           let tab = IslandTab(rawValue: CommandLine.arguments[index + 1]) {
            state.selectedTab = tab
        }
        panelController = NotchPanelController(state: state)
        configureStatusItem()
        panelController?.show()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func menuWillOpen(_ menu: NSMenu) {
        state.refreshLoginItemStatus()
        loginMenuItem?.state = state.loginItemEnabled ? .on : .off
    }

    @objc private func toggleIsland() {
        panelController?.toggle()
    }

    @objc private func openTools() {
        panelController?.showTools()
    }

    @objc private func toggleLogin() {
        state.toggleLoginItem()
        loginMenuItem?.state = state.loginItemEnabled ? .on : .off
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "capsule.tophalf.filled", accessibilityDescription: "IslandBar")

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: "Открыть IslandBar", action: #selector(toggleIsland), keyEquivalent: "o").target = self
        menu.addItem(withTitle: "Инструменты и настройки", action: #selector(openTools), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        let login = menu.addItem(withTitle: "Запускать при входе", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = state.loginItemEnabled ? .on : .off
        loginMenuItem = login
        menu.addItem(.separator())
        menu.addItem(withTitle: "Завершить IslandBar", action: #selector(quit), keyEquivalent: "q").target = self
        item.menu = menu
        statusItem = item
    }
}
