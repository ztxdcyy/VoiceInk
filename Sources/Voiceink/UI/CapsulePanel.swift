import AppKit

enum CapsuleState {
    case hidden
    case recording
    case waitingForResult
    case error(String)
}

class CapsulePanel: NSPanel {
    private let effectView: NSVisualEffectView
    private let waveformView: WaveformView
    private let transcriptLabel: TranscriptLabel
    private let spinner: NSProgressIndicator

    private let capsuleHeight: CGFloat = 56
    private let cornerRadius: CGFloat = 28
    private let waveformSize = NSSize(width: 44, height: 32)
    private let leadingPadding: CGFloat = 16
    private let innerSpacing: CGFloat = 12
    private let trailingPadding: CGFloat = 16
    private let minTextWidth: CGFloat = 160

    private(set) var state: CapsuleState = .hidden

    // MARK: - Init

    init() {
        // Setup visual effect view
        effectView = NSVisualEffectView()
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = cornerRadius
        effectView.layer?.masksToBounds = true

        // Waveform
        waveformView = WaveformView(frame: NSRect(
            x: leadingPadding,
            y: (capsuleHeight - waveformSize.height) / 2,
            width: waveformSize.width,
            height: waveformSize.height
        ))

        // Transcript label
        let labelX = leadingPadding + waveformSize.width + innerSpacing
        transcriptLabel = TranscriptLabel(frame: NSRect(
            x: labelX,
            y: 0,
            width: minTextWidth,
            height: capsuleHeight
        ))

        // Spinner (hidden by default)
        spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.frame = NSRect(
            x: leadingPadding + (waveformSize.width - 20) / 2,
            y: (capsuleHeight - 20) / 2,
            width: 20,
            height: 20
        )
        spinner.isHidden = true

        // Calculate initial width
        let initialWidth = leadingPadding + waveformSize.width + innerSpacing + minTextWidth + trailingPadding

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: initialWidth, height: capsuleHeight),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )

        configurePanel()
        setupSubviews()

        transcriptLabel.onWidthChanged = { [weak self] newWidth in
            self?.updatePanelWidth(textWidth: newWidth)
        }
    }

    private func configurePanel() {
        level = .statusBar
        isFloatingPanel = true
        hidesOnDeactivate = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }

    private func setupSubviews() {
        guard let contentView = self.contentView else { return }

        effectView.frame = contentView.bounds
        effectView.autoresizingMask = [.width, .height]
        contentView.addSubview(effectView)

        effectView.addSubview(waveformView)
        effectView.addSubview(transcriptLabel)
        effectView.addSubview(spinner)
    }

    // MARK: - State Management

    func setState(_ newState: CapsuleState) {
        state = newState

        switch newState {
        case .hidden:
            hideAnimated()

        case .recording:
            transcriptLabel.reset()
            waveformView.reset()
            waveformView.isHidden = false
            waveformView.startAnimating()
            spinner.isHidden = true
            spinner.stopAnimation(nil)
            ensureVisible()

        case .waitingForResult:
            waveformView.stopAnimating()
            waveformView.isHidden = true
            spinner.isHidden = false
            spinner.startAnimation(nil)
            ensureVisible()

        case .error(let message):
            waveformView.stopAnimating()
            waveformView.isHidden = true
            spinner.isHidden = true
            spinner.stopAnimation(nil)
            transcriptLabel.text = message
            ensureVisible()

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                if case .error = self?.state {
                    self?.setState(.hidden)
                }
            }
        }
    }

    /// Ensure the panel is on screen and visible
    private func ensureVisible() {
        if !isVisible {
            positionNearCursor()
            alphaValue = 0
            contentView?.layer?.setAffineTransform(CGAffineTransform(scaleX: 0.8, y: 0.8))
            orderFrontRegardless()

            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.35
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                context.allowsImplicitAnimation = true
                self.animator().alphaValue = 1
                self.contentView?.layer?.setAffineTransform(.identity)
            })
        }
    }

    // MARK: - Content Updates

    func updateWaveformLevel(_ level: Float) {
        waveformView.updateLevel(level)
    }

    func updateTranscript(_ text: String) {
        transcriptLabel.text = text
    }

    // MARK: - Panel Width

    private func updatePanelWidth(textWidth: CGFloat) {
        let totalWidth = leadingPadding + waveformSize.width + innerSpacing + textWidth + trailingPadding

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

            var newFrame = self.frame
            let widthDelta = totalWidth - newFrame.width
            newFrame.size.width = totalWidth
            newFrame.origin.x -= widthDelta / 2 // keep centered
            self.animator().setFrame(newFrame, display: true)

            // Update transcript label width
            let labelX = leadingPadding + waveformSize.width + innerSpacing
            transcriptLabel.animator().frame = NSRect(
                x: labelX,
                y: 0,
                width: textWidth,
                height: capsuleHeight
            )
        })
    }

    // MARK: - Position

    private func positionNearCursor() {
        if let caretRect = Self.getCaretRect() {
            guard let screen = NSScreen.main else {
                positionAtScreenBottom()
                return
            }
            let screenFrame = screen.frame
            AppLogger.shared.log("[Capsule] caretRect=\(caretRect), screenFrame=\(screenFrame)")

            // Place capsule below the caret, offset 8px down
            var x = caretRect.origin.x
            var y = caretRect.origin.y - frame.height - 8

            // Keep within screen bounds
            if x + frame.width > screenFrame.maxX - 10 {
                x = screenFrame.maxX - frame.width - 10
            }
            if x < screenFrame.origin.x + 10 {
                x = screenFrame.origin.x + 10
            }
            if y < screenFrame.origin.y + 10 {
                y = caretRect.maxY + 8
            }

            setFrameOrigin(NSPoint(x: x, y: y))
            return
        }

        AppLogger.shared.log("[Capsule] caret not found, falling back to screen bottom center")
        positionAtScreenBottom()
    }

    private func positionAtScreenBottom() {
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let panelWidth = max(frame.width, 248)
        let x = screenFrame.origin.x + (screenFrame.width - panelWidth) / 2
        let y = screenFrame.origin.y + 80
        AppLogger.shared.log("[Capsule] fallback position: x=\(x), y=\(y), panelW=\(panelWidth), screenFrame=\(screenFrame)")
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    /// Use Accessibility API (system-wide) to get the caret position.
    /// Uses AXUIElementCreateSystemWide to avoid frontmostApplication issues.
    private static func getCaretRect() -> NSRect? {
        let systemElement = AXUIElementCreateSystemWide()

        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(systemElement, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success else {
            AppLogger.shared.log("[Capsule] AX: cannot get focused element")
            return nil
        }

        let element = focusedElement as! AXUIElement

        var selectedRange: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRange) == .success else {
            AppLogger.shared.log("[Capsule] AX: cannot get selected text range")
            return nil
        }

        var boundsValue: AnyObject?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            selectedRange!,
            &boundsValue
        ) == .success else {
            AppLogger.shared.log("[Capsule] AX: cannot get bounds for range")
            return nil
        }

        var rect = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &rect) else {
            AppLogger.shared.log("[Capsule] AX: cannot extract CGRect")
            return nil
        }

        // AX coordinates: origin at top-left of main screen. Convert to AppKit (bottom-left).
        guard let screen = NSScreen.main else { return nil }
        let flippedY = screen.frame.height - rect.origin.y - rect.size.height
        return NSRect(x: rect.origin.x, y: flippedY, width: rect.size.width, height: rect.size.height)
    }

    // MARK: - Animations

    private func hideAnimated() {
        guard let layer = contentView?.layer else {
            orderOut(nil)
            return
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            context.allowsImplicitAnimation = true
            self.animator().alphaValue = 0
            layer.setAffineTransform(CGAffineTransform(scaleX: 0.85, y: 0.85))
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
            layer.setAffineTransform(.identity)
            self?.alphaValue = 1
            self?.waveformView.stopAnimating()
            self?.waveformView.reset()
        })
    }
}
