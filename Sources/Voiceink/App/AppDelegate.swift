import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarManager: MenuBarManager!
    private var sessionCoordinator: SessionCoordinator!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 0. Setup standard Edit menu for Cmd+C/V/X/A in text fields
        setupEditMenu()

        // 1. Load settings
        _ = SettingsStore.shared

        // 2. Setup menu bar
        menuBarManager = MenuBarManager.shared

        // 3. Setup session coordinator
        sessionCoordinator = SessionCoordinator()
        FnKeyMonitor.shared.delegate = sessionCoordinator

        // 4. Check permissions — this may show guide window
        PermissionManager.shared.checkAndRequestPermissions()

        // 5. Try to start Fn monitor now (may fail if not yet authorized)
        FnKeyMonitor.shared.start()

        // 6. Also listen for permission granted later (after user completes guide)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onAccessibilityGranted),
            name: .accessibilityPermissionGranted,
            object: nil
        )
    }

    @objc private func onAccessibilityGranted() {
        AppLogger.shared.log("[AppDelegate] accessibilityPermissionGranted — (re)starting FnKeyMonitor")
        FnKeyMonitor.shared.stop()
        FnKeyMonitor.shared.start()
    }

    /// LSUIElement apps have no main menu, so Cmd+V/C/X/A don't work in text fields.
    /// We create a hidden Edit menu to provide the standard editing responder chain.
    private func setupEditMenu() {
        let mainMenu = NSMenu()

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")

        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    func applicationWillTerminate(_ notification: Notification) {
        FnKeyMonitor.shared.stop()
    }
}
