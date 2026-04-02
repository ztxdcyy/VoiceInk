import AppKit

class TranscriptLabel: NSView {
    private let textField: NSTextField
    private let minWidth: CGFloat = 160
    private let maxWidth: CGFloat = 560

    var onWidthChanged: ((CGFloat) -> Void)?

    var text: String {
        get { textField.stringValue }
        set {
            textField.stringValue = newValue
            updateWidth()
        }
    }

    override init(frame frameRect: NSRect) {
        textField = NSTextField(labelWithString: "")
        super.init(frame: frameRect)
        setupTextField()
    }

    required init?(coder: NSCoder) {
        textField = NSTextField(labelWithString: "")
        super.init(coder: coder)
        setupTextField()
    }

    private func setupTextField() {
        textField.font = .systemFont(ofSize: 14, weight: .medium)
        textField.textColor = .white
        textField.backgroundColor = .clear
        textField.isBezeled = false
        textField.isEditable = false
        textField.isSelectable = false
        textField.lineBreakMode = .byTruncatingTail
        textField.maximumNumberOfLines = 1
        textField.translatesAutoresizingMaskIntoConstraints = false

        addSubview(textField)

        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: leadingAnchor),
            textField.trailingAnchor.constraint(equalTo: trailingAnchor),
            textField.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    private func updateWidth() {
        let attributedString = NSAttributedString(
            string: textField.stringValue,
            attributes: [.font: textField.font!]
        )
        let textWidth = attributedString.size().width + 8 // small padding
        let clampedWidth = min(max(textWidth, minWidth), maxWidth)
        onWidthChanged?(clampedWidth)
    }

    func reset() {
        textField.stringValue = ""
        onWidthChanged?(minWidth)
    }
}
