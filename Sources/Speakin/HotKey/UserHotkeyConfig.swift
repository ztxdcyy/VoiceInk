import CoreGraphics
import Foundation

/// Represents a user-configured trigger hotkey for Speakin.
/// A `nil` value in SettingsStore means "use the default Fn key".
struct UserHotkeyConfig: Codable, Equatable {
    /// Raw key code from CGEvent.getIntegerValueField(.keyboardEventKeycode).
    /// Stored as Int64 to match the CGEvent API directly.
    /// For modifier-only hotkeys this distinguishes L/R variants
    /// (e.g. Right Option = 61, Left Option = 58).
    let keyCode: Int64

    /// CGEventFlags.rawValue — only the four semantic modifier bits are stored:
    /// maskCommand, maskShift, maskAlternate, maskControl.
    let modifierFlagsRaw: UInt64

    /// Human-readable label shown in the settings UI, e.g. "⌥ Right Option" or "F13".
    let displayName: String

    /// When true the hotkey fires on `flagsChanged` events (modifier key press/release).
    /// When false it fires on `keyDown`/`keyUp` events (regular or function key).
    let isModifierOnly: Bool

    var modifierFlags: CGEventFlags { CGEventFlags(rawValue: modifierFlagsRaw) }
}

// MARK: - Normalisation helpers

extension UserHotkeyConfig {
    /// The four modifier bits we care about.  Strips transient bits (caps lock, numpad, etc.)
    static let semanticModifiers: CGEventFlags = [
        .maskCommand, .maskShift, .maskAlternate, .maskControl
    ]

    /// Normalises raw CGEventFlags to just the four semantic bits.
    static func normalizeFlags(_ flags: CGEventFlags) -> CGEventFlags {
        flags.intersection(semanticModifiers)
    }
}

// MARK: - Known modifier-only keycodes

extension UserHotkeyConfig {
    /// Maps well-known modifier keyCodes to their display names and CGEventFlags.
    /// Both left and right variants are included.
    static let knownModifierKeys: [Int64: (displayName: String, cgFlags: CGEventFlags)] = [
        58: ("⌥ Left Option",   .maskAlternate),
        61: ("⌥ Right Option",  .maskAlternate),
        55: ("⌘ Left Command",  .maskCommand),
        54: ("⌘ Right Command", .maskCommand),
        56: ("⇧ Left Shift",    .maskShift),
        60: ("⇧ Right Shift",   .maskShift),
        59: ("⌃ Left Control",  .maskControl),
        62: ("⌃ Right Control", .maskControl),
    ]

    /// Function key keyCodes that are valid as hotkeys without any modifier.
    static let functionKeyCodes: Set<Int64> = [
        105, // F13
        107, // F14
        113, // F15
        114, // F16 / Help
        115, // F17 / Home
        116, // F18 / Page Up
        117, // F19 / Delete
        119, // F20 / End
    ]

    /// Display names for function keys.
    static let functionKeyNames: [Int64: String] = [
        105: "F13",
        107: "F14",
        113: "F15",
        114: "F16",
        115: "F17",
        116: "F18",
        117: "F19 / Del",
        119: "F20 / End",
    ]
}
