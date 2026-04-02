import AppKit

class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var apiKeyField: NSTextField!
    private var modelField: NSTextField!
    private var statusLabel: NSTextField!

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Voiceink Settings"
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

    // MARK: - UI Setup

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        let padding: CGFloat = 20
        let fieldHeight: CGFloat = 24
        let labelHeight: CGFloat = 17
        let fieldWidth: CGFloat = 380

        var y: CGFloat = 170

        // API Key label
        let apiKeyLabel = makeLabel("DashScope API Key", frame: NSRect(x: padding, y: y, width: fieldWidth, height: labelHeight))
        contentView.addSubview(apiKeyLabel)

        y -= fieldHeight + 4

        // API Key field
        apiKeyField = NSTextField(frame: NSRect(x: padding, y: y, width: fieldWidth, height: fieldHeight))
        apiKeyField.placeholderString = "sk-xxxxxxxxxxxxxxxxxxxxxxxx"
        apiKeyField.font = .systemFont(ofSize: 13)
        contentView.addSubview(apiKeyField)

        y -= labelHeight + 16

        // Model label
        let modelLabel = makeLabel("Model", frame: NSRect(x: padding, y: y, width: fieldWidth, height: labelHeight))
        contentView.addSubview(modelLabel)

        y -= fieldHeight + 4

        // Model field
        modelField = NSTextField(frame: NSRect(x: padding, y: y, width: fieldWidth, height: fieldHeight))
        modelField.placeholderString = "qwen-omni-turbo-latest"
        modelField.font = .systemFont(ofSize: 13)
        contentView.addSubview(modelField)

        y -= 40

        // Status label
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.frame = NSRect(x: padding, y: y, width: 200, height: labelHeight)
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        contentView.addSubview(statusLabel)

        // Buttons
        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveSettings))
        saveButton.frame = NSRect(x: 330, y: y - 4, width: 70, height: 28)
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        contentView.addSubview(saveButton)

        let testButton = NSButton(title: "Test", target: self, action: #selector(testConnection))
        testButton.frame = NSRect(x: 255, y: y - 4, width: 70, height: 28)
        testButton.bezelStyle = .rounded
        contentView.addSubview(testButton)
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
        modelField.stringValue = SettingsStore.shared.model
    }

    @objc private func saveSettings() {
        let apiKey = apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        SettingsStore.shared.apiKey = apiKey.isEmpty ? nil : apiKey

        let model = modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        SettingsStore.shared.model = model.isEmpty ? "qwen-omni-turbo-latest" : model

        statusLabel.stringValue = "Settings saved."
        statusLabel.textColor = .systemGreen
        NotificationCenter.default.post(name: .voiceInkSettingsSaved, object: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.window?.close()
        }
    }

    // MARK: - Test Connection

    @objc private func testConnection() {
        let apiKey = apiKeyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !apiKey.isEmpty else {
            statusLabel.stringValue = "Please enter an API key."
            statusLabel.textColor = .systemRed
            return
        }

        statusLabel.stringValue = "Connecting..."
        statusLabel.textColor = .secondaryLabelColor

        let model = modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelName = model.isEmpty ? "qwen-omni-turbo-latest" : model
        let urlString = "wss://dashscope.aliyuncs.com/api-ws/v1/realtime?model=\(modelName)"

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

        // Listen for the first message (session.created)
        task.receive { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let message):
                    if case .string(let text) = message, text.contains("session.created") {
                        self?.statusLabel.stringValue = "Connection successful!"
                        self?.statusLabel.textColor = .systemGreen
                    } else {
                        self?.statusLabel.stringValue = "Unexpected response."
                        self?.statusLabel.textColor = .systemOrange
                    }
                case .failure(let error):
                    self?.statusLabel.stringValue = "Error: \(error.localizedDescription)"
                    self?.statusLabel.textColor = .systemRed
                }
                task.cancel(with: .goingAway, reason: nil)
            }
        }

        // Timeout after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            if self?.statusLabel.stringValue == "Connecting..." {
                self?.statusLabel.stringValue = "Connection timed out."
                self?.statusLabel.textColor = .systemRed
                task.cancel(with: .goingAway, reason: nil)
            }
        }
    }
}
