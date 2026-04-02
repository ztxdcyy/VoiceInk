import CoreGraphics
import Foundation

protocol FnKeyMonitorDelegate: AnyObject {
    func fnKeyDidPress()
    func fnKeyDidRelease()
}

class FnKeyMonitor {
    static let shared = FnKeyMonitor()

    weak var delegate: FnKeyMonitorDelegate?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var fnPressed = false

    private init() {}

    // MARK: - Start / Stop

    func start() {
        guard eventTap == nil else {
            AppLogger.shared.log("[FnKey] start() skipped — tap already exists")
            return
        }

        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)

        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: fnEventCallback,
            userInfo: userInfo
        ) else {
            AppLogger.shared.log("[FnKey] FAILED to create CGEvent tap — no accessibility permission?")
            return
        }

        eventTap = tap

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        AppLogger.shared.log("[FnKey] Monitor started successfully. delegate=\(delegate != nil ? "set" : "nil")")
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        fnPressed = false
        print("[Voiceink] Fn key monitor stopped.")
    }

    // MARK: - Event Handling

    fileprivate func handleFlagsChanged(_ event: CGEvent) -> Bool {
        let flags = event.flags
        let isFn = flags.contains(.maskSecondaryFn)

        if isFn && !fnPressed {
            fnPressed = true
            AppLogger.shared.log("[FnKey] Fn DOWN detected")
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.fnKeyDidPress()
            }
            return true
        } else if !isFn && fnPressed {
            fnPressed = false
            AppLogger.shared.log("[FnKey] Fn UP detected")
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.fnKeyDidRelease()
            }
            return true
        }

        return false
    }

    /// Re-enable the tap if macOS disables it (e.g. after sleep)
    func reEnableIfNeeded() {
        if let tap = eventTap {
            if !CGEvent.tapIsEnabled(tap: tap) {
                CGEvent.tapEnable(tap: tap, enable: true)
                print("[Voiceink] Re-enabled CGEvent tap.")
            }
        }
    }
}

// MARK: - C Callback

private func fnEventCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {

    // Handle tap disabled by system
    if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout {
        if let userInfo = userInfo {
            let monitor = Unmanaged<FnKeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            monitor.reEnableIfNeeded()
        }
        return Unmanaged.passRetained(event)
    }

    guard type == .flagsChanged, let userInfo = userInfo else {
        return Unmanaged.passRetained(event)
    }

    let monitor = Unmanaged<FnKeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    let shouldSuppress = monitor.handleFlagsChanged(event)

    if shouldSuppress {
        return nil // swallow event to prevent emoji picker
    }

    return Unmanaged.passRetained(event)
}
