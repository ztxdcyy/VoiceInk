import AppKit

class WaveformView: NSView {
    // MARK: - Configuration
    private let barCount = 5
    private let barWeights: [CGFloat] = [0.5, 0.8, 1.0, 0.75, 0.55]
    private let barWidth: CGFloat = 3.0
    private let barSpacing: CGFloat = 3.0
    private let barCornerRadius: CGFloat = 1.5
    private let minBarHeight: CGFloat = 4.0
    private let maxBarHeight: CGFloat = 28.0

    // Envelope parameters
    private let attackRate: CGFloat = 0.40
    private let releaseRate: CGFloat = 0.15
    private let jitterAmount: CGFloat = 0.04

    // MARK: - State
    private var smoothedLevel: CGFloat = 0.0
    private var barHeights: [CGFloat]
    private var displayTimer: Timer?

    // MARK: - Init

    override init(frame frameRect: NSRect) {
        barHeights = Array(repeating: minBarHeight, count: barCount)
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        barHeights = Array(repeating: 4.0, count: 5)
        super.init(coder: coder)
    }

    // MARK: - Level Update

    func updateLevel(_ rawRMS: Float) {
        let normalized = min(CGFloat(rawRMS) * 3.5, 1.0)

        if normalized > smoothedLevel {
            smoothedLevel += (normalized - smoothedLevel) * attackRate
        } else {
            smoothedLevel += (normalized - smoothedLevel) * releaseRate
        }

        for i in 0..<barCount {
            let jitter = CGFloat.random(in: -jitterAmount...jitterAmount)
            let height = minBarHeight + (maxBarHeight - minBarHeight)
                * smoothedLevel * barWeights[i]
                * (1.0 + jitter)
            barHeights[i] = max(minBarHeight, min(maxBarHeight, height))
        }

        needsDisplay = true
    }

    func reset() {
        smoothedLevel = 0
        barHeights = Array(repeating: minBarHeight, count: barCount)
        needsDisplay = true
    }

    // MARK: - Display Timer

    func startAnimating() {
        stopAnimating()
        displayTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.needsDisplay = true
        }
    }

    func stopAnimating() {
        displayTimer?.invalidate()
        displayTimer = nil
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }

        let totalBarsWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barSpacing
        let startX = (bounds.width - totalBarsWidth) / 2.0
        let centerY = bounds.height / 2.0

        context.setFillColor(NSColor.white.withAlphaComponent(0.9).cgColor)

        for i in 0..<barCount {
            let x = startX + CGFloat(i) * (barWidth + barSpacing)
            let height = barHeights[i]
            let y = centerY - height / 2.0

            let rect = CGRect(x: x, y: y, width: barWidth, height: height)
            let path = CGPath(roundedRect: rect, cornerWidth: barCornerRadius, cornerHeight: barCornerRadius, transform: nil)
            context.addPath(path)
            context.fillPath()
        }
    }
}
