import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarManager: MenuBarManager!
    private var sessionCoordinator: SessionCoordinator!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 0. Setup standard Edit menu for Cmd+C/V/X/A in text fields
        setupEditMenu()

        // 0.5. Register signal handler so CGEvent tap is ALWAYS cleaned up,
        //      even when process is killed by SIGTERM (e.g. `pkill`, `make run`).
        //      Without this, the tap can outlive the process and hijack keyboard.
        setupSignalHandler()

        // 1. Load settings
        _ = SettingsStore.shared

        // 2. Setup menu bar
        menuBarManager = MenuBarManager.shared

        // 3. Setup session coordinator
        sessionCoordinator = SessionCoordinator()
        HotkeyMonitor.shared.delegate = sessionCoordinator

        // 4. Check permissions — this may show guide window
        PermissionManager.shared.checkAndRequestPermissions()

        // 5. Try to start hotkey monitor now (may fail if not yet authorized)
        HotkeyMonitor.shared.start(with: SettingsStore.shared.customHotkey)

        // 6. Listen for permission granted later (after user completes guide)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onAccessibilityGranted),
            name: .accessibilityPermissionGranted,
            object: nil
        )

        // 7. Listen for hotkey changes from Settings
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onHotkeyChanged),
            name: .speakinHotkeyChanged,
            object: nil
        )
    }

    @objc private func onAccessibilityGranted() {
        AppLogger.shared.log("[AppDelegate] accessibilityPermissionGranted — (re)starting HotkeyMonitor")
        HotkeyMonitor.shared.stop()
        HotkeyMonitor.shared.start(with: SettingsStore.shared.customHotkey)
    }

    @objc private func onHotkeyChanged() {
        let newHotkey = SettingsStore.shared.customHotkey
        AppLogger.shared.log("[AppDelegate] hotkey changed → \(newHotkey?.displayName ?? "Fn (default)")")
        HotkeyMonitor.shared.updateHotkey(newHotkey)
    }

    /// Register a SIGTERM handler that disables and removes the CGEvent tap
    /// before the process exits. This prevents "keyboard hijack" when the
    /// process is killed externally (e.g. `pkill`, `make run`, Activity Monitor).
    private func setupSignalHandler() {
        let sigTermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        sigTermSource.setEventHandler {
            AppLogger.shared.log("[AppDelegate] SIGTERM received — cleaning up tap")
            HotkeyMonitor.shared.stop()
            // Give a tiny moment for tap removal to take effect, then exit
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                exit(0)
            }
        }
        sigTermSource.resume()
        // Must ignore default SIGTERM handling so DispatchSource gets it
        signal(SIGTERM, SIG_IGN)
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
        HotkeyMonitor.shared.stop()
    }
}
