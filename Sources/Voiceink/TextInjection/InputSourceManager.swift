import Carbon
import AppKit

class InputSourceManager {

    /// Get current input source
    static func currentInputSource() -> TISInputSource? {
        return TISCopyCurrentKeyboardInputSource()?.takeRetainedValue()
    }

    /// Check if current input source is CJK (Chinese, Japanese, Korean)
    static func isCJKInputSource() -> Bool {
        guard let source = currentInputSource() else { return false }
        guard let langs = getProperty(source, key: kTISPropertyInputSourceLanguages) as? [String] else {
            return false
        }
        let cjkPrefixes = ["zh", "ja", "ko"]
        return langs.contains { lang in
            cjkPrefixes.contains { lang.hasPrefix($0) }
        }
    }

    /// Switch to ASCII-capable input source (e.g., ABC, US keyboard)
    /// Returns the previous input source for later restoration
    static func switchToASCII() -> TISInputSource? {
        let previous = currentInputSource()

        guard let sources = TISCreateASCIICapableInputSourceList()?.takeRetainedValue() as? [TISInputSource],
              let asciiSource = sources.first else {
            return previous
        }

        TISSelectInputSource(asciiSource)
        return previous
    }

    /// Restore to a previously saved input source
    static func restore(_ inputSource: TISInputSource) {
        TISSelectInputSource(inputSource)
    }

    // MARK: - Private

    private static func getProperty(_ source: TISInputSource, key: CFString) -> Any? {
        guard let raw = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue()
    }
}
