import AppKit
import CoreGraphics
import Foundation

protocol HotkeyMonitorDelegate: AnyObject {
    func hotkeyDidPress()
    func hotkeyDidRelease()
}

class HotkeyMonitor {
    static let shared = HotkeyMonitor()

    weak var delegate: HotkeyMonitorDelegate?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var hotkeyPressed = false

    /// Caret rect captured synchronously in the CGEvent callback (before event is swallowed).
    /// Accessed from CGEvent callback thread + main thread, protected by the fact that
    /// main.async reads happen after the write.
    private(set) var lastCaretRect: NSRect?

    /// nil = Fn-key mode (default). Non-nil = user-configured hotkey.
    private var registeredHotkey: UserHotkeyConfig?

    private init() {}

    // MARK: - Start / Stop

    func start(with hotkey: UserHotkeyConfig? = nil) {
        guard eventTap == nil else {
            AppLogger.shared.log("[Hotkey] start() skipped — tap already exists")
            return
        }

        registeredHotkey = hotkey
        let eventMask = buildEventMask(for: hotkey)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: hotkeyEventCallback,
            userInfo: userInfo
        ) else {
            AppLogger.shared.log("[Hotkey] FAILED to create CGEvent tap — no accessibility permission?")
            return
        }

        eventTap = tap

        // Sync initial pressed state with hardware before enabling
        syncHardwareState()

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        AppLogger.shared.log("[Hotkey] Monitor started. hotkey=\(hotkey?.displayName ?? "Fn (default)") delegate=\(delegate != nil ? "set" : "nil")")
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        hotkeyPressed = false
        AppLogger.shared.log("[Hotkey] monitor stopped, tap destroyed")
    }

    /// Update the registered hotkey at runtime without restarting, when possible.
    /// If the new hotkey requires a different event mask, the tap is restarted.
    func updateHotkey(_ newHotkey: UserHotkeyConfig?) {
        let oldNeedsKeyEvents = registeredHotkey.map { !$0.isModifierOnly } ?? false
        let newNeedsKeyEvents = newHotkey.map { !$0.isModifierOnly } ?? false

        if oldNeedsKeyEvents != newNeedsKeyEvents {
            // Event mask change requires tap rebuild
            AppLogger.shared.log("[Hotkey] eventMask change — restarting tap for hotkey: \(newHotkey?.displayName ?? "Fn")")
            stop()
            start(with: newHotkey)
        } else {
            // Compatible mask — swap config atomically
            registeredHotkey = newHotkey
            hotkeyPressed = false  // reset state on hotkey change
            AppLogger.shared.log("[Hotkey] hotkey updated (no tap restart): \(newHotkey?.displayName ?? "Fn")")
        }
    }

    // MARK: - Recording support

    /// Temporarily disable the tap during hotkey recording to prevent interference.
    func pauseForRecording() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            AppLogger.shared.log("[Hotkey] tap paused for recording")
        }
    }

    /// Re-enable the tap after hotkey recording is complete.
    func resumeAfterRecording() {
        hotkeyPressed = false  // always reset — we may have missed key-up events while paused
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
            AppLogger.shared.log("[Hotkey] tap resumed after recording")
        }
    }

    // MARK: - Self-healing

    /// Re-enable the tap if macOS disables it (e.g. after sleep/wake or timeout).
    /// MUST sync hotkeyPressed with actual hardware state first to prevent stuck-key suppression.
    func reEnableIfNeeded() {
        if let tap = eventTap, !CGEvent.tapIsEnabled(tap: tap) {
            syncHardwareState()
            CGEvent.tapEnable(tap: tap, enable: true)
            AppLogger.shared.log("[Hotkey] tap re-enabled, synced hotkeyPressed=\(hotkeyPressed)")
        }
    }

    // MARK: - Event dispatch (called from C callback)

    /// Returns true if the event should be suppressed (swallowed).
    fileprivate func handleEvent(type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .flagsChanged:
            return handleFlagsChanged(event)
        case .keyDown:
            return handleKeyDown(event)
        case .keyUp:
            return handleKeyUp(event)
        default:
            return false
        }
    }

    // MARK: - Private event handlers

    private func handleFlagsChanged(_ event: CGEvent) -> Bool {
        if let hotkey = registeredHotkey, hotkey.isModifierOnly {
            return handleFlagsChangedForCustomModifier(event, hotkey: hotkey)
        } else {
            return handleFlagsChangedForFn(event)
        }
    }

    /// Fn-key mode: identical logic to the original FnKeyMonitor.
    private func handleFlagsChangedForFn(_ event: CGEvent) -> Bool {
        let flags = event.flags
        let isFn = flags.contains(.maskSecondaryFn)

        if isFn && !hotkeyPressed {
            hotkeyPressed = true
            AppLogger.shared.log("[Hotkey] Fn DOWN")
            let mouseRect = Self.mousePositionRect()
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.lastCaretRect = Self.captureCaretRect() ?? mouseRect
                self.delegate?.hotkeyDidPress()
            }
            // Suppress pure-Fn presses (prevents emoji picker).
            // If other modifiers are held, let the event through.
            let hasOtherModifiers = !flags.intersection(Self.nonFnModifiers).isEmpty
            return !hasOtherModifiers

        } else if !isFn && hotkeyPressed {
            hotkeyPressed = false
            AppLogger.shared.log("[Hotkey] Fn UP")
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.hotkeyDidRelease()
            }
            let hasOtherModifiers = !flags.intersection(Self.nonFnModifiers).isEmpty
            return !hasOtherModifiers
        }

        return false
    }

    /// Modifier-only custom hotkey (e.g. Right Option).
    /// SAFETY: Never suppress modifier events — the system must see state changes.
    private func handleFlagsChangedForCustomModifier(_ event: CGEvent, hotkey: UserHotkeyConfig) -> Bool {
        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flagsMatch = flags.contains(hotkey.modifierFlags)
        let keyCodeMatches = (keyCode == hotkey.keyCode)

        if flagsMatch && keyCodeMatches && !hotkeyPressed {
            hotkeyPressed = true
            AppLogger.shared.log("[Hotkey] custom modifier DOWN (\(hotkey.displayName))")
            let mouseRect = Self.mousePositionRect()
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.lastCaretRect = Self.captureCaretRect() ?? mouseRect
                self.delegate?.hotkeyDidPress()
            }
        } else if !flagsMatch && hotkeyPressed && keyCodeMatches {
            hotkeyPressed = false
            AppLogger.shared.log("[Hotkey] custom modifier UP (\(hotkey.displayName))")
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.hotkeyDidRelease()
            }
        }

        // Never suppress modifier events — return false always
        return false
    }

    /// keyDown-based custom hotkey (e.g. F13).
    /// Suppress the event so the target app doesn't see the key press.
    private func handleKeyDown(_ event: CGEvent) -> Bool {
        guard let hotkey = registeredHotkey, !hotkey.isModifierOnly else { return false }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == hotkey.keyCode else { return false }

        // Normalise flags to just the four semantic bits
        let eventFlags = UserHotkeyConfig.normalizeFlags(event.flags)
        let requiredFlags = UserHotkeyConfig.normalizeFlags(hotkey.modifierFlags)
        guard eventFlags == requiredFlags else { return false }

        if !hotkeyPressed {
            hotkeyPressed = true
            AppLogger.shared.log("[Hotkey] keyDown hotkey pressed (\(hotkey.displayName))")
            let mouseRect = Self.mousePositionRect()
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.lastCaretRect = Self.captureCaretRect() ?? mouseRect
                self.delegate?.hotkeyDidPress()
            }
        }
        return true  // suppress — don't let the key reach the focused app
    }

    /// keyUp-based custom hotkey release.
    private func handleKeyUp(_ event: CGEvent) -> Bool {
        guard let hotkey = registeredHotkey, !hotkey.isModifierOnly else { return false }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == hotkey.keyCode, hotkeyPressed else { return false }

        hotkeyPressed = false
        AppLogger.shared.log("[Hotkey] keyDown hotkey released (\(hotkey.displayName))")
        DispatchQueue.main.async { [weak self] in
            self?.delegate?.hotkeyDidRelease()
        }
        return true  // suppress matching key-up
    }

    // MARK: - Helpers

    private static let nonFnModifiers: CGEventFlags = [
        .maskCommand, .maskShift, .maskAlternate, .maskControl, .maskAlphaShift
    ]

    /// Sync hotkeyPressed with actual hardware state.
    private func syncHardwareState() {
        if let hotkey = registeredHotkey {
            if hotkey.isModifierOnly {
                let currentFlags = CGEventSource.flagsState(.combinedSessionState)
                hotkeyPressed = currentFlags.contains(hotkey.modifierFlags)
            } else {
                // keyDown-based: cannot read from flagsState — default to not held
                hotkeyPressed = false
            }
        } else {
            // Fn mode
            hotkeyPressed = CGEventSource.flagsState(.combinedSessionState).contains(.maskSecondaryFn)
        }
    }

    /// Build the CGEventMask based on the hotkey type.
    private func buildEventMask(for config: UserHotkeyConfig?) -> CGEventMask {
        // flagsChanged is always needed (Fn + modifier-only hotkeys)
        var mask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)
        if let config = config, !config.isModifierOnly {
            // keyDown-based hotkeys also need keyDown + keyUp
            mask |= (1 << CGEventType.keyDown.rawValue)
            mask |= (1 << CGEventType.keyUp.rawValue)
        }
        return mask
    }

    /// Capture the caret rect using Accessibility API.
    /// Uses a short messaging timeout (150ms) to avoid blocking if the target app is unresponsive.
    /// Should be called from main thread (moved out of CGEvent callback for safety).
    private static func captureCaretRect() -> NSRect? {
        let systemElement = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemElement, 0.15)

        var focusedElement: AnyObject?
        guard AXUIElementCopyAttributeValue(systemElement, kAXFocusedUIElementAttribute as CFString, &focusedElement) == .success else {
            AppLogger.shared.log("[Hotkey] AX: cannot get focused element")
            return nil
        }

        let element = focusedElement as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.15)

        var selectedRange: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRange) == .success else {
            AppLogger.shared.log("[Hotkey] AX: cannot get selected text range")
            return nil
        }

        var boundsValue: AnyObject?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            selectedRange!,
            &boundsValue
        ) == .success else {
            AppLogger.shared.log("[Hotkey] AX: cannot get bounds for range")
            return nil
        }

        var rect = CGRect.zero
        guard AXValueGetValue(boundsValue as! AXValue, .cgRect, &rect) else {
            return nil
        }

        // AX coordinates: origin at top-left of main screen. Convert to AppKit (bottom-left).
        guard let screen = NSScreen.main else { return nil }
        let flippedY = screen.frame.height - rect.origin.y - rect.size.height
        let result = NSRect(x: rect.origin.x, y: flippedY, width: rect.size.width, height: rect.size.height)
        AppLogger.shared.log("[Hotkey] captured caret: \(result)")
        return result
    }

    /// Fallback: use the current mouse position as an approximate caret location.
    private static func mousePositionRect() -> NSRect? {
        let mouseLocation = NSEvent.mouseLocation
        AppLogger.shared.log("[Hotkey] fallback to mouse position: \(mouseLocation)")
        return NSRect(x: mouseLocation.x, y: mouseLocation.y, width: 0, height: 18)
    }
}

// MARK: - C Callback

private func hotkeyEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {

    // Handle tap disabled by system (timeout or user input)
    if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout {
        if let userInfo = userInfo {
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            monitor.reEnableIfNeeded()
        }
        return Unmanaged.passRetained(event)
    }

    guard let userInfo = userInfo else {
        return Unmanaged.passRetained(event)
    }

    let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    let shouldSuppress = monitor.handleEvent(type: type, event: event)

    if shouldSuppress {
        return nil
    }

    return Unmanaged.passRetained(event)
}
