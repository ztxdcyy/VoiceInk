import AppKit
import Carbon
import CoreGraphics

class TextInjector {

    /// Inject text into the currently focused input field
    static func inject(text: String) {
        guard !text.isEmpty else { return }

        // 1. Backup current pasteboard contents
        let pasteboard = NSPasteboard.general
        let backupItems = backupPasteboard(pasteboard)

        // 2. Write transcribed text to pasteboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // 3. Handle CJK input source - temporarily switch to ASCII
        var previousInputSource: TISInputSource?
        if InputSourceManager.isCJKInputSource() {
            previousInputSource = InputSourceManager.switchToASCII()
            // Small delay to let the input source switch take effect
            usleep(50_000) // 50ms
        }

        // 4. Simulate Cmd+V
        simulatePaste()

        // 5. Restore input source and pasteboard after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            // Restore input source
            if let source = previousInputSource {
                InputSourceManager.restore(source)
            }

            // Restore pasteboard after additional delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                restorePasteboard(pasteboard, items: backupItems)
            }
        }
    }

    // MARK: - Simulate Paste

    private static func simulatePaste() {
        let vKeyCode: CGKeyCode = 9 // 'V' key

        let source = CGEventSource(stateID: .hidSystemState)

        // Key down with Cmd
        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true) {
            keyDown.flags = .maskCommand
            keyDown.post(tap: .cgAnnotatedSessionEventTap)
        }

        // Key up with Cmd
        if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false) {
            keyUp.flags = .maskCommand
            keyUp.post(tap: .cgAnnotatedSessionEventTap)
        }
    }

    // MARK: - Pasteboard Backup / Restore

    private static func backupPasteboard(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        guard let items = pasteboard.pasteboardItems else { return [] }

        return items.compactMap { item in
            let newItem = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    newItem.setData(data, forType: type)
                }
            }
            return newItem
        }
    }

    private static func restorePasteboard(_ pasteboard: NSPasteboard, items: [NSPasteboardItem]) {
        pasteboard.clearContents()
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }
}
