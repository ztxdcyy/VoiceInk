import AppKit

class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var apiKeyField: NSTextField!
    private var statusLabel: NSTextField!
    private var apiKeyLabel: NSTextField!
    private var saveButton: NSButton!
    private var testButton: NSButton!
    private var brandIconView: NSImageView!

    // Hotkey UI
    private var triggerKeyLabel: NSTextField!
    private var triggerKeyDisplayLabel: NSTextField!
    private var recordHotkeyButton: NSButton!
    private var resetHotkeyButton: NSButton!

    // Hotkey recording state
    private var isRecordingHotkey = false
    private var localEventMonitor: Any?

    // MARK: - Localized strings keyed by language code

    private static let strings: [String: [String: String]] = [
        "zh-CN": [
            "title": "Speakin 设置",
            "apiKeyLabel": "DashScope API Key",
            "save": "保存",
            "test": "测试",
            "saved": "设置已保存。",
            "enterKey": "请输入 API Key。",
            "connecting": "连接中...",
            "success": "连接成功！",
            "invalidKey": "API Key 无效或配额不足。",
            "unexpected": "意外的响应。",
            "timeout": "连接超时。",
            "triggerKey": "触发按键",
            "recordHotkey": "录制按键",
            "resetHotkey": "恢复默认 (Fn)",
            "recordingPrompt": "请按下目标按键...",
            "hotkeyNone": "Fn（默认）",
            "hotkeyRecorded": "按键已保存。",
            "hotkeyInvalid": "该按键无法使用，请重试。",
        ],
        "en": [
            "title": "Speakin Settings",
            "apiKeyLabel": "DashScope API Key",
            "save": "Save",
            "test": "Test",
            "saved": "Settings saved.",
            "enterKey": "Please enter an API key.",
            "connecting": "Connecting...",
            "success": "Connection successful!",
            "invalidKey": "API key invalid or quota exceeded.",
            "unexpected": "Unexpected response.",
            "timeout": "Connection timed out.",
            "triggerKey": "Trigger Key",
            "recordHotkey": "Record Key",
            "resetHotkey": "Reset to Fn",
            "recordingPrompt": "Press any key...",
            "hotkeyNone": "Fn (default)",
            "hotkeyRecorded": "Key saved.",
            "hotkeyInvalid": "This key cannot be used, try another.",
        ],
        "ja": [
            "title": "Speakin 設定",
            "apiKeyLabel": "DashScope API Key",
            "save": "保存",
            "test": "テスト",
            "saved": "設定を保存しました。",
            "enterKey": "API Key を入力してください。",
            "connecting": "接続中...",
            "success": "接続成功！",
            "invalidKey": "API Key が無効、またはクォータ超過です。",
            "unexpected": "予期しない応答です。",
            "timeout": "接続がタイムアウトしました。",
            "triggerKey": "トリガーキー",
            "recordHotkey": "キーを録音",
            "resetHotkey": "Fn にリセット",
            "recordingPrompt": "キーを押してください...",
            "hotkeyNone": "Fn（デフォルト）",
            "hotkeyRecorded": "キーを保存しました。",
            "hotkeyInvalid": "このキーは使用できません。",
        ],
        "ko": [
            "title": "Speakin 설정",
            "apiKeyLabel": "DashScope API Key",
            "save": "저장",
            "test": "테스트",
            "saved": "설정이 저장되었습니다.",
            "enterKey": "API Key를 입력하세요.",
            "connecting": "연결 중...",
            "success": "연결 성공!",
            "invalidKey": "API Key가 유효하지 않거나 할당량을 초과했습니다.",
            "unexpected": "예상치 못한 응답입니다.",
            "timeout": "연결 시간이 초과되었습니다.",
            "triggerKey": "트리거 키",
            "recordHotkey": "키 녹화",
            "resetHotkey": "Fn으로 재설정",
            "recordingPrompt": "키를 누르세요...",
            "hotkeyNone": "Fn (기본값)",
            "hotkeyRecorded": "키가 저장되었습니다.",
            "hotkeyInvalid": "이 키는 사용할 수 없습니다.",
        ],
    ]

    private func L(_ key: String) -> String {
        let lang = SettingsStore.shared.language
        return Self.strings[lang]?[key]
            ?? Self.strings["en"]![key]!
    }

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 310),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        setupUI()
        loadSettings()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    override func showWindow(_ sender: Any?) {
        refreshLocalization()
        super.showWindow(sender)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // Always exit recording mode when the window is closed
        if isRecordingHotkey {
            exitRecordingMode()
        }
    }

    // MARK: - UI Setup

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let padding: CGFloat = 20
        let fieldHeight: CGFloat = 24
        let labelHeight: CGFloat = 17
        let fieldWidth: CGFloat = 380

        // Brand icon + name at top (shifted up 90pt from original y=175 → y=265)
        var y: CGFloat = 265

        brandIconView = NSImageView(frame: NSRect(x: padding, y: y - 4, width: 32, height: 32))
        brandIconView.imageScaling = .scaleProportionallyUpOrDown
        brandIconView.image = Bundle.main.image(forResource: "bird_icon_32")
        contentView.addSubview(brandIconView)

        let brandLabel = NSTextField(labelWithString: "Speakin")
        brandLabel.frame = NSRect(x: padding + 38, y: y, width: 200, height: 22)
        brandLabel.font = .systemFont(ofSize: 17, weight: .bold)
        brandLabel.textColor = .labelColor
        contentView.addSubview(brandLabel)

        y = 230  // was 140

        // API Key label
        apiKeyLabel = makeLabel("", frame: NSRect(x: padding, y: y, width: fieldWidth, height: labelHeight))
        contentView.addSubview(apiKeyLabel)

        y -= fieldHeight + 4

        // API Key field
        apiKeyField = NSTextField(frame: NSRect(x: padding, y: y, width: fieldWidth, height: fieldHeight))
        apiKeyField.placeholderString = "sk-xxxxxxxxxxxxxxxxxxxxxxxx"
        apiKeyField.font = .systemFont(ofSize: 13)
        contentView.addSubview(apiKeyField)

        y -= 40

        // Status label
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.frame = NSRect(x: padding, y: y, width: 200, height: labelHeight)
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        contentView.addSubview(statusLabel)

        // Save / Test buttons (aligned to status row)
        saveButton = NSButton(title: "", target: self, action: #selector(saveSettings))
        saveButton.frame = NSRect(x: 330, y: y - 4, width: 70, height: 28)
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        contentView.addSubview(saveButton)

        testButton = NSButton(title: "", target: self, action: #selector(testConnection))
        testButton.frame = NSRect(x: 255, y: y - 4, width: 70, height: 28)
        testButton.bezelStyle = .rounded
        contentView.addSubview(testButton)

        // ── Separator ──────────────────────────────────────────────────────────
        let separator = NSBox(frame: NSRect(x: padding, y: y - 28, width: fieldWidth, height: 1))
        separator.boxType = .separator
        contentView.addSubview(separator)

        // ── Trigger Key section ────────────────────────────────────────────────
        // Section label
        triggerKeyLabel = makeLabel("", frame: NSRect(x: padding, y: y - 50, width: 200, height: labelHeight))
        contentView.addSubview(triggerKeyLabel)

        // Current hotkey display
        triggerKeyDisplayLabel = NSTextField(labelWithString: "")
        triggerKeyDisplayLabel.frame = NSRect(x: padding, y: y - 75, width: fieldWidth, height: fieldHeight)
        triggerKeyDisplayLabel.font = .monospacedSystemFont(ofSize: 14, weight: .medium)
        triggerKeyDisplayLabel.textColor = .secondaryLabelColor
        contentView.addSubview(triggerKeyDisplayLabel)

        // Record / Reset buttons
        recordHotkeyButton = NSButton(title: "", target: self, action: #selector(startRecordingHotkey))
        recordHotkeyButton.frame = NSRect(x: padding, y: y - 110, width: 110, height: 28)
        recordHotkeyButton.bezelStyle = .rounded
        contentView.addSubview(recordHotkeyButton)

        resetHotkeyButton = NSButton(title: "", target: self, action: #selector(resetHotkey))
        resetHotkeyButton.frame = NSRect(x: padding + 118, y: y - 110, width: 120, height: 28)
        resetHotkeyButton.bezelStyle = .rounded
        contentView.addSubview(resetHotkeyButton)

        refreshLocalization()
    }

    private func refreshLocalization() {
        window?.title = L("title")
        apiKeyLabel.stringValue = L("apiKeyLabel")
        saveButton.title = L("save")
        testButton.title = L("test")
        triggerKeyLabel.stringValue = L("triggerKey")
        recordHotkeyButton.title = L("recordHotkey")
        resetHotkeyButton.title = L("resetHotkey")
        refreshHotkeyDisplay()
    }

    private func refreshHotkeyDisplay() {
        if let hotkey = SettingsStore.shared.customHotkey {
            triggerKeyDisplayLabel.stringValue = hotkey.displayName
            triggerKeyDisplayLabel.textColor = .labelColor
        } else {
            triggerKeyDisplayLabel.stringValue = L("hotkeyNone")
            triggerKeyDisplayLabel.textColor = .secondaryLabelColor
        }
    }

    private func makeLabel(_ text: String, frame: NSRect) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.frame = frame
        label.font = .systemFont(ofSize: 13, weight: .medium)
        return label
    }

    // MARK: - Load / Save

    private func loadSettings() {
        apiKeyField.stringValue = SettingsStore.shared.apiKey ?? ""
    }

    @objc private func saveSettings() {
        let apiKey = apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        SettingsStore.shared.apiKey = apiKey.isEmpty ? nil : apiKey

        statusLabel.stringValue = L("saved")
        statusLabel.textColor = .systemGreen
        NotificationCenter.default.post(name: .speakinSettingsSaved, object: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.window?.close()
        }
    }

    // MARK: - Hotkey recording

    @objc private func startRecordingHotkey() {
        guard !isRecordingHotkey else { return }
        isRecordingHotkey = true

        triggerKeyDisplayLabel.stringValue = L("recordingPrompt")
        triggerKeyDisplayLabel.textColor = .secondaryLabelColor
        recordHotkeyButton.isEnabled = false
        resetHotkeyButton.isEnabled = false
        statusLabel.stringValue = ""

        // Disable the global CGEvent tap during recording to prevent event interference.
        // The settings window is in the foreground; no push-to-talk will happen now.
        HotkeyMonitor.shared.pauseForRecording()

        // Capture key events scoped to this window only — does not affect other apps.
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) {
            [weak self] event in
            self?.handleRecordingEvent(event)
            return nil  // consume during recording
        }
    }

    private func handleRecordingEvent(_ event: NSEvent) {
        if event.type == .flagsChanged {
            handleRecordingFlagsChanged(event)
        } else if event.type == .keyDown {
            handleRecordingKeyDown(event)
        }
    }

    private func handleRecordingFlagsChanged(_ event: NSEvent) {
        let keyCode = Int64(event.keyCode)
        guard let info = UserHotkeyConfig.knownModifierKeys[keyCode] else { return }

        // Only fire on key-down (modifier appearing in flags), not on release
        let currentFlags = event.modifierFlags
        let hasModifier: Bool
        switch info.cgFlags {
        case .maskAlternate:  hasModifier = currentFlags.contains(.option)
        case .maskCommand:    hasModifier = currentFlags.contains(.command)
        case .maskShift:      hasModifier = currentFlags.contains(.shift)
        case .maskControl:    hasModifier = currentFlags.contains(.control)
        default:              hasModifier = false
        }
        guard hasModifier else { return }  // this is the release event, ignore

        let candidate = UserHotkeyConfig(
            keyCode: keyCode,
            modifierFlagsRaw: info.cgFlags.rawValue,
            displayName: info.displayName,
            isModifierOnly: true
        )
        commitHotkey(candidate)
    }

    private func handleRecordingKeyDown(_ event: NSEvent) {
        let keyCode = Int64(event.keyCode)

        // Build normalized CGEventFlags from NSEvent modifierFlags
        var cgFlags = CGEventFlags()
        let nsFlags = event.modifierFlags
        if nsFlags.contains(.command) { cgFlags.insert(.maskCommand) }
        if nsFlags.contains(.shift)   { cgFlags.insert(.maskShift) }
        if nsFlags.contains(.option)  { cgFlags.insert(.maskAlternate) }
        if nsFlags.contains(.control) { cgFlags.insert(.maskControl) }
        let normalizedFlags = UserHotkeyConfig.normalizeFlags(cgFlags)

        // Determine display name
        let displayName: String
        if let fnName = UserHotkeyConfig.functionKeyNames[keyCode] {
            displayName = fnName
        } else {
            // Build modifier prefix + key character
            var prefix = ""
            if normalizedFlags.contains(.maskControl)  { prefix += "⌃" }
            if normalizedFlags.contains(.maskAlternate) { prefix += "⌥" }
            if normalizedFlags.contains(.maskShift)    { prefix += "⇧" }
            if normalizedFlags.contains(.maskCommand)  { prefix += "⌘" }
            let char = event.charactersIgnoringModifiers?.uppercased() ?? "?"
            displayName = prefix + char
        }

        let candidate = UserHotkeyConfig(
            keyCode: keyCode,
            modifierFlagsRaw: normalizedFlags.rawValue,
            displayName: displayName,
            isModifierOnly: false
        )

        if validateHotkey(candidate) {
            commitHotkey(candidate)
        } else {
            statusLabel.stringValue = L("hotkeyInvalid")
            statusLabel.textColor = .systemRed
            // Stay in recording mode so user can try again
        }
    }

    /// Returns true if the candidate hotkey is safe to use.
    private func validateHotkey(_ candidate: UserHotkeyConfig) -> Bool {
        let flags = candidate.modifierFlags
        let keyCode = candidate.keyCode

        // Accept function keys (F13–F20) without any modifier
        if UserHotkeyConfig.functionKeyCodes.contains(keyCode) {
            return true
        }

        // Reject Cmd+single-letter combos (system reserved space)
        let cmdOnly = CGEventFlags([.maskCommand])
        if flags.intersection(UserHotkeyConfig.semanticModifiers) == cmdOnly {
            return false
        }

        // Reject keys with no modifiers at all (too easy to accidentally trigger)
        if flags.intersection(UserHotkeyConfig.semanticModifiers).isEmpty {
            return false
        }

        return true
    }

    private func commitHotkey(_ config: UserHotkeyConfig) {
        exitRecordingMode()
        SettingsStore.shared.customHotkey = config
        refreshHotkeyDisplay()

        statusLabel.stringValue = L("hotkeyRecorded")
        statusLabel.textColor = .systemGreen
        NotificationCenter.default.post(name: .speakinHotkeyChanged, object: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self else { return }
            if self.statusLabel.stringValue == self.L("hotkeyRecorded") {
                self.statusLabel.stringValue = ""
            }
        }
    }

    private func exitRecordingMode() {
        isRecordingHotkey = false
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
        }
        HotkeyMonitor.shared.resumeAfterRecording()
        recordHotkeyButton.isEnabled = true
        resetHotkeyButton.isEnabled = true
        refreshHotkeyDisplay()
    }

    @objc private func resetHotkey() {
        SettingsStore.shared.customHotkey = nil
        refreshHotkeyDisplay()
        statusLabel.stringValue = ""
        NotificationCenter.default.post(name: .speakinHotkeyChanged, object: nil)
    }

    // MARK: - Test Connection

    @objc private func testConnection() {
        let apiKey = apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            statusLabel.stringValue = L("enterKey")
            statusLabel.textColor = .systemRed
            return
        }

        let connectingText = L("connecting")
        statusLabel.stringValue = connectingText
        statusLabel.textColor = .secondaryLabelColor

        let urlString = "wss://dashscope.aliyuncs.com/api-ws/v1/inference"

        guard let url = URL(string: urlString) else {
            statusLabel.stringValue = "Invalid URL."
            statusLabel.textColor = .systemRed
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: request)
        task.resume()

        // Send a minimal run-task to verify the API key is valid
        let taskID = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let runTask: [String: Any] = [
            "header": [
                "action": "run-task",
                "task_id": taskID,
                "streaming": "duplex"
            ],
            "payload": [
                "task_group": "audio",
                "task": "asr",
                "function": "recognition",
                "model": "paraformer-realtime-v2",
                "parameters": [
                    "sample_rate": 16000,
                    "format": "pcm"
                ] as [String: Any],
                "input": [String: Any]()
            ]
        ]

        if let data = try? JSONSerialization.data(withJSONObject: runTask),
           let jsonString = String(data: data, encoding: .utf8) {
            task.send(.string(jsonString)) { _ in }
        }

        // Listen for the first message (task-started or task-failed)
        task.receive { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch result {
                case .success(let message):
                    if case .string(let text) = message, text.contains("task-started") {
                        self.statusLabel.stringValue = self.L("success")
                        self.statusLabel.textColor = .systemGreen
                    } else if case .string(let text) = message, text.contains("task-failed") {
                        self.statusLabel.stringValue = self.L("invalidKey")
                        self.statusLabel.textColor = .systemRed
                    } else {
                        self.statusLabel.stringValue = self.L("unexpected")
                        self.statusLabel.textColor = .systemOrange
                    }
                case .failure(let error):
                    self.statusLabel.stringValue = "Error: \(error.localizedDescription)"
                    self.statusLabel.textColor = .systemRed
                }
                task.cancel(with: .goingAway, reason: nil)
            }
        }

        // Timeout after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self = self else { return }
            if self.statusLabel.stringValue == connectingText {
                self.statusLabel.stringValue = self.L("timeout")
                self.statusLabel.textColor = .systemRed
                task.cancel(with: .goingAway, reason: nil)
            }
        }
    }
}
