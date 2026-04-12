import AppKit
import AVFoundation

class PermissionManager {
    static let shared = PermissionManager()

    private(set) var accessibilityGranted = false
    private(set) var microphoneGranted = false

    private var guideWindowController: PermissionGuideWindowController?
    private var accessibilityPollingTimer: Timer?
    private let logger = PermissionDebugLogger.shared

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSettingsSaved),
            name: .speakinSettingsSaved,
            object: nil
        )
    }

    func checkAndRequestPermissions() {
        logger.log("checkAndRequestPermissions start")
        checkAccessibility()
        checkMicrophone()
    }

    // MARK: - Accessibility

    /// The real test: try to create a CGEvent tap with .defaultTap (same as FnKeyMonitor).
    /// .listenOnly may succeed when .defaultTap fails, so we must test the exact same mode.
    private func probeAccessibilityPermission() -> Bool {
        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { _, _, event, _ in Unmanaged.passRetained(event) },
            userInfo: nil
        ) else {
            return false
        }
        CFMachPortInvalidate(tap)
        return true
    }

    private func checkAccessibility() {
        accessibilityGranted = probeAccessibilityPermission()
        logger.log("checkAccessibility probe=\(accessibilityGranted)")

        let apiKey = SettingsStore.shared.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if accessibilityGranted && !apiKey.isEmpty {
            logger.log("checkAccessibility: all set, skipping guide")
            return
        }

        if accessibilityGranted {
            showGuideWindow()
            guideWindowController?.setAuthorizedAndEnterAPIStep()
            stopAccessibilityPolling()
        } else {
            // Trigger system prompt on first launch
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)

            showGuideWindow()
            guideWindowController?.applyStep(.accessibility)
            startAccessibilityPolling()
        }
    }

    private func showGuideWindow() {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)

            if self.guideWindowController == nil {
                let controller = PermissionGuideWindowController()
                controller.onOpenSettings = { [weak self] in
                    self?.openAccessibilitySettings()
                }
                controller.onOpenAPISettings = {
                    let settingsWC = SettingsWindowController.shared
                    settingsWC.showWindow(nil)
                    settingsWC.window?.level = .floating + 1
                    settingsWC.window?.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
                controller.onRecheck = { [weak self] in
                    self?.recheckAccessibilityPermission()
                }
                controller.onStartUsing = { [weak self] in
                    self?.finishGuideFlowByUserAction()
                }
                self.guideWindowController = controller
            }

            self.guideWindowController?.showWindow(nil)
            self.guideWindowController?.window?.makeKeyAndOrderFront(nil)
        }
    }

    private func finishGuideFlowByUserAction() {
        let apiKey = SettingsStore.shared.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !apiKey.isEmpty else {
            guideWindowController?.setAPIMissingHint()
            logger.log("finishGuideFlowByUserAction blocked: api key missing")
            return
        }

        logger.log("finishGuideFlowByUserAction success — showing allDone")
        guideWindowController?.showAllDone()

        // Show "all done" screen for 2s then close
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.guideWindowController?.close()
            self?.guideWindowController = nil
        }
    }

    private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        logger.log("openAccessibilitySettings")
        NSWorkspace.shared.open(url)
    }

    private func recheckAccessibilityPermission() {
        accessibilityGranted = probeAccessibilityPermission()
        logger.log("recheckAccessibility probe=\(accessibilityGranted)")

        if accessibilityGranted {
            guideWindowController?.setAuthorizedAndEnterAPIStep()
            NotificationCenter.default.post(name: .accessibilityPermissionGranted, object: nil)
            stopAccessibilityPolling()
        } else {
            guideWindowController?.setRecheckFailedHint(
                "仍未检测到权限。请在系统设置中先移除 Speakin，再重新添加并开启。"
            )
        }
    }

    private func startAccessibilityPolling() {
        stopAccessibilityPolling()
        accessibilityPollingTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let granted = self.probeAccessibilityPermission()
            if granted {
                self.accessibilityGranted = true
                self.logger.log("polling: probe succeeded")
                DispatchQueue.main.async {
                    self.guideWindowController?.setAuthorizedAndEnterAPIStep()
                    NotificationCenter.default.post(name: .accessibilityPermissionGranted, object: nil)
                }
                self.stopAccessibilityPolling()
            }
        }
    }

    private func stopAccessibilityPolling() {
        accessibilityPollingTimer?.invalidate()
        accessibilityPollingTimer = nil
    }

    // MARK: - Settings Observer

    @objc private func handleSettingsSaved() {
        guideWindowController?.refreshAPIStatus()
    }

    // MARK: - Microphone

    private func checkMicrophone() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphoneGranted = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                self?.microphoneGranted = granted
                if granted {
                    NotificationCenter.default.post(name: .microphonePermissionGranted, object: nil)
                }
            }
        case .denied, .restricted:
            microphoneGranted = false
        @unknown default:
            break
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let accessibilityPermissionGranted = Notification.Name("Speakin.accessibilityPermissionGranted")
    static let microphonePermissionGranted = Notification.Name("Speakin.microphonePermissionGranted")
    static let speakinSettingsSaved = Notification.Name("Speakin.settingsSaved")
    static let speakinHotkeyChanged = Notification.Name("Speakin.hotkeyChanged")
}
