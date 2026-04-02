import AppKit

final class PermissionGuideWindowController: NSWindowController {
    enum GuideStep {
        case accessibility
        case accessibilityDone   // 授权成功过渡态
        case api
        case allDone             // 全部完成过渡态
    }

    var onOpenSettings: (() -> Void)?
    var onOpenAPISettings: (() -> Void)?
    var onRecheck: (() -> Void)?
    var onStartUsing: (() -> Void)?

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let descriptionLabel = NSTextField(wrappingLabelWithString: "")
    private let statusBanner = NSView()
    private let statusIcon = NSTextField(labelWithString: "")
    private let statusText = NSTextField(labelWithString: "")

    private var systemSettingsButton: NSButton?
    private var apiSettingsButton: NSButton?
    private var primaryButton: NSButton?

    private(set) var step: GuideStep = .accessibility

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Voiceink 引导"
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating
        super.init(window: window)
        setupUI()
        applyStep(.accessibility)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UI

    private func setupUI() {
        guard let contentView = window?.contentView else { return }
        let padding: CGFloat = 24

        // Icon
        iconView.frame = NSRect(x: padding, y: 316, width: 32, height: 32)
        iconView.image = Self.emojiImage("🎤", size: 32)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        contentView.addSubview(iconView)

        // Title
        titleLabel.frame = NSRect(x: padding + 40, y: 320, width: 540, height: 24)
        titleLabel.font = .systemFont(ofSize: 18, weight: .bold)
        contentView.addSubview(titleLabel)

        // Description
        descriptionLabel.frame = NSRect(x: padding, y: 138, width: 592, height: 170)
        descriptionLabel.font = .systemFont(ofSize: 13)
        descriptionLabel.textColor = .labelColor
        contentView.addSubview(descriptionLabel)

        // Status banner (rounded green/orange/gray bar)
        statusBanner.frame = NSRect(x: padding, y: 94, width: 592, height: 36)
        statusBanner.wantsLayer = true
        statusBanner.layer?.cornerRadius = 8
        contentView.addSubview(statusBanner)

        statusIcon.frame = NSRect(x: 12, y: 6, width: 24, height: 24)
        statusIcon.font = .systemFont(ofSize: 18)
        statusIcon.alignment = .center
        statusBanner.addSubview(statusIcon)

        statusText.frame = NSRect(x: 40, y: 8, width: 540, height: 20)
        statusText.font = .systemFont(ofSize: 13, weight: .medium)
        statusText.isBezeled = false
        statusText.isEditable = false
        statusText.drawsBackground = false
        statusBanner.addSubview(statusText)

        // Buttons row
        let btnY: CGFloat = 32

        let openButton = NSButton(title: "打开系统设置", target: self, action: #selector(openSettingsTapped))
        openButton.frame = NSRect(x: padding, y: btnY, width: 170, height: 36)
        openButton.bezelStyle = .rounded
        contentView.addSubview(openButton)
        systemSettingsButton = openButton

        let apiButton = NSButton(title: "打开 API 配置", target: self, action: #selector(openAPISettingsTapped))
        apiButton.frame = NSRect(x: padding, y: btnY, width: 170, height: 36)
        apiButton.bezelStyle = .rounded
        contentView.addSubview(apiButton)
        apiSettingsButton = apiButton

        let doneButton = NSButton(title: "我已完成授权，重新检查", target: self, action: #selector(primaryTapped))
        doneButton.frame = NSRect(x: 380, y: btnY, width: 236, height: 36)
        doneButton.bezelStyle = .rounded
        contentView.addSubview(doneButton)
        primaryButton = doneButton
    }

    // MARK: - Steps

    func applyStep(_ newStep: GuideStep) {
        step = newStep

        switch newStep {
        case .accessibility:
            iconView.image = Self.emojiImage("🔐", size: 32)
            titleLabel.stringValue = "第一步：开启辅助功能权限"
            descriptionLabel.stringValue = """
为了监听 Fn 键并将语音文字粘贴到当前输入框，Voiceink 需要"辅助功能"权限。

操作步骤：
1) 点击下方"打开系统设置"
2) 在"隐私与安全性 → 辅助功能"列表中找到 Voiceink
3) 如果 Voiceink 已存在但检测失败：先点"-"移除，再点"+"重新添加并开启
4) 返回本窗口，点击"我已完成授权，重新检查"
"""
            setStatusBanner(icon: "⏳", text: "等待授权...", color: NSColor.systemGray.withAlphaComponent(0.15), textColor: .secondaryLabelColor)

            systemSettingsButton?.isHidden = false
            apiSettingsButton?.isHidden = true
            primaryButton?.title = "我已完成授权，重新检查"
            primaryButton?.isEnabled = true

        case .accessibilityDone:
            iconView.image = Self.emojiImage("✅", size: 32)
            titleLabel.stringValue = "第一步：辅助功能权限 — 已完成！"
            descriptionLabel.stringValue = """
辅助功能权限授权成功！

即将进入第二步：配置 API...
"""
            setStatusBanner(icon: "✅", text: "辅助功能权限已授权成功！", color: NSColor.systemGreen.withAlphaComponent(0.15), textColor: .systemGreen)

            systemSettingsButton?.isHidden = true
            apiSettingsButton?.isHidden = true
            primaryButton?.isHidden = true

        case .api:
            iconView.image = Self.emojiImage("🔑", size: 32)
            titleLabel.stringValue = "第二步：配置百炼 API"
            descriptionLabel.stringValue = """
辅助功能权限已完成。现在请配置百炼 API：

1) 点击下方"打开 API 配置"
2) 填写 DashScope API Key（必填）
3) 如有需要修改模型，然后点击保存
4) 回到本窗口，点击"我已完成 API 配置，开始使用"
"""
            refreshAPIStatus()

            systemSettingsButton?.isHidden = true
            apiSettingsButton?.isHidden = false
            primaryButton?.isHidden = false
            primaryButton?.title = "我已完成 API 配置，开始使用"
            primaryButton?.isEnabled = true

        case .allDone:
            iconView.image = Self.emojiImage("🎉", size: 32)
            titleLabel.stringValue = "设置全部完成！"
            descriptionLabel.stringValue = """
Voiceink 已准备就绪。

使用方法：按住 Fn 键说话，松开后文字将自动输入到当前光标位置。

你可以随时通过菜单栏图标调整语言和设置。祝你使用愉快！
"""
            setStatusBanner(icon: "🎉", text: "所有配置已完成，Voiceink 已就绪！", color: NSColor.systemGreen.withAlphaComponent(0.15), textColor: .systemGreen)

            systemSettingsButton?.isHidden = true
            apiSettingsButton?.isHidden = true
            primaryButton?.isHidden = false
            primaryButton?.title = "开始使用 Voiceink"
            primaryButton?.isEnabled = true
        }
    }

    // MARK: - Status Banner

    private func setStatusBanner(icon: String, text: String, color: NSColor, textColor: NSColor) {
        statusBanner.layer?.backgroundColor = color.cgColor
        statusIcon.stringValue = icon
        statusText.stringValue = text
        statusText.textColor = textColor
    }

    func setChecking() {
        setStatusBanner(icon: "🔄", text: "正在检查权限...", color: NSColor.systemBlue.withAlphaComponent(0.1), textColor: .systemBlue)
        primaryButton?.isEnabled = false
        primaryButton?.title = "检查中..."
    }

    func setRecheckFailedHint(_ message: String? = nil) {
        setStatusBanner(
            icon: "⚠️",
            text: message ?? "仍未授权，请确认 Voiceink 开关已打开。",
            color: NSColor.systemOrange.withAlphaComponent(0.12),
            textColor: .systemOrange
        )
        primaryButton?.isEnabled = true
        primaryButton?.title = "我已完成授权，重新检查"
    }

    func setAuthorizedAndEnterAPIStep() {
        applyStep(.accessibilityDone)

        // 停留 1.2s 让用户看到成功状态，再自动切到第二步
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.applyStep(.api)
        }
    }

    func setAPIMissingHint() {
        setStatusBanner(
            icon: "⚠️",
            text: "尚未配置 API Key，请先点击「打开 API 配置」。",
            color: NSColor.systemOrange.withAlphaComponent(0.12),
            textColor: .systemOrange
        )
    }

    func refreshAPIStatus() {
        let apiKey = SettingsStore.shared.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if apiKey.isEmpty {
            setStatusBanner(icon: "⏳", text: "等待配置 API Key...", color: NSColor.systemGray.withAlphaComponent(0.15), textColor: .secondaryLabelColor)
        } else {
            setStatusBanner(icon: "✅", text: "API Key 已配置！", color: NSColor.systemGreen.withAlphaComponent(0.15), textColor: .systemGreen)
        }
    }

    func showAllDone() {
        applyStep(.allDone)
    }

    // MARK: - Actions

    @objc private func openSettingsTapped() {
        onOpenSettings?()
    }

    @objc private func openAPISettingsTapped() {
        onOpenAPISettings?()
    }

    @objc private func primaryTapped() {
        switch step {
        case .accessibility:
            setChecking()
            onRecheck?()
        case .allDone:
            onStartUsing?()
        default:
            onStartUsing?()
        }
    }

    // MARK: - Helpers

    private static func emojiImage(_ emoji: String, size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size * 0.75),
            .paragraphStyle: paragraph
        ]
        (emoji as NSString).draw(in: NSRect(x: 0, y: size * 0.05, width: size, height: size * 0.9), withAttributes: attrs)
        image.unlockFocus()
        return image
    }
}
