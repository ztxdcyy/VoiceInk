import AppKit
import ServiceManagement

class MenuBarManager {
    private var statusItem: NSStatusItem!
    private var menu: NSMenu!

    static let shared = MenuBarManager()

    init() {
        setupStatusItem()
        buildMenu()
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Voiceink")
            button.image?.size = NSSize(width: 18, height: 18)
        }
    }

    func setRecording(_ recording: Bool) {
        DispatchQueue.main.async { [weak self] in
            let symbolName = recording ? "mic.badge.plus" : "mic.fill"
            self?.statusItem.button?.image = NSImage(
                systemSymbolName: symbolName,
                accessibilityDescription: "Voiceink"
            )
        }
    }

    // MARK: - Menu

    private func buildMenu() {
        menu = NSMenu()

        // Language submenu
        let languageItem = NSMenuItem(title: "Language", action: nil, keyEquivalent: "")
        let languageMenu = NSMenu()

        let languages: [(String, String)] = [
            ("简体中文", "zh-CN"),
            ("English", "en"),
            ("繁體中文", "zh-TW"),
            ("日本語", "ja"),
            ("한국어", "ko"),
        ]

        for (name, code) in languages {
            let item = NSMenuItem(title: name, action: #selector(languageSelected(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = code
            if SettingsStore.shared.language == code {
                item.state = .on
            }
            languageMenu.addItem(item)
        }

        languageItem.submenu = languageMenu
        menu.addItem(languageItem)

        menu.addItem(NSMenuItem.separator())

        // Settings
        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        // Launch at Login
        let launchItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin(_:)), keyEquivalent: "")
        launchItem.target = self
        launchItem.state = SettingsStore.shared.launchAtLogin ? .on : .off
        menu.addItem(launchItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit Voiceink", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Actions

    @objc private func languageSelected(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        SettingsStore.shared.language = code

        // Update checkmarks
        if let languageMenu = sender.menu {
            for item in languageMenu.items {
                item.state = (item.representedObject as? String) == code ? .on : .off
            }
        }
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        let newValue = !SettingsStore.shared.launchAtLogin
        SettingsStore.shared.launchAtLogin = newValue
        sender.state = newValue ? .on : .off

        if #available(macOS 13.0, *) {
            do {
                if newValue {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("[Voiceink] Failed to update login item: \(error)")
            }
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
