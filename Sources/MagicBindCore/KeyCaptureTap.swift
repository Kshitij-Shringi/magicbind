import CoreGraphics
import Foundation

/// The single capture the C tap callback forwards to. `@convention(c)`
/// callbacks can't capture context, so this is how the callback finds its
/// owner — same pattern as `MouseButtonMonitor`.
private var activeKeyCapture: KeyCaptureTap?

private func magicBindKeyCaptureCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        activeKeyCapture?.reenable()
        return Unmanaged.passUnretained(event)
    }

    guard let capture = activeKeyCapture else {
        return Unmanaged.passUnretained(event)
    }

    let flags = ShortcutModifiers(rawValue: event.flags.rawValue)
        .intersection(.displayable)

    switch type {
    case .flagsChanged:
        // Passed through: swallowing modifier changes would desync every other
        // app's idea of which modifiers are held.
        capture.deliverModifiers(flags)
        return Unmanaged.passUnretained(event)

    case .keyDown:
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        capture.deliverKey(keyCode, flags)
        // Swallowed, so recording ⌘⇧4 records it instead of taking a
        // screenshot, and ⌘Q records instead of quitting.
        return nil

    case .keyUp:
        // The matching key-up is swallowed too. Letting it through on its own
        // leaves apps seeing a release for a press they never got.
        return nil

    default:
        return Unmanaged.passUnretained(event)
    }
}

/// Captures a single keyboard shortcut, including combinations the operating
/// system would otherwise intercept.
///
/// The obvious implementations don't work, in escalating order of subtlety:
///
/// - `NSEvent.addLocalMonitorForEvents` misses **menu key equivalents** — ⌘W,
///   ⌘Q and friends are claimed before a monitor runs.
/// - A first-responder `NSView` overriding `performKeyEquivalent(with:)` fixes
///   those, but still misses **system-reserved hotkeys** like the screenshot
///   shortcuts, which macOS matches above the application, and depends on the
///   view actually holding first-responder status.
///
/// An event tap sits above all of that and doesn't care about focus. It is
/// active rather than listen-only, because the keypress must be *swallowed* —
/// otherwise recording ⌘⇧4 also fires a screenshot.
///
/// - Important: This tap is alive **only while a shortcut field is armed**, and
///   is torn down the instant a key is captured or recording is cancelled. It
///   is never running during normal use. See SECURITY.md.
public final class KeyCaptureTap {
    public enum CaptureError: Error, LocalizedError {
        case tapCreationFailed
        case alreadyRunning

        public var errorDescription: String? {
            switch self {
            case .tapCreationFailed:
                return """
                    MagicBind couldn't capture keys. This needs Accessibility \
                    permission — grant it in System Settings > Privacy & \
                    Security > Accessibility, then relaunch.
                    """
            case .alreadyRunning:
                return "A shortcut is already being recorded."
            }
        }
    }

    /// Called as modifiers change while armed, so the field can show them live.
    public typealias ModifiersHandler = (ShortcutModifiers) -> Void

    /// Called once, with the captured key. The tap stops immediately after.
    public typealias KeyHandler = (UInt16, ShortcutModifiers) -> Void

    private let onModifiers: ModifiersHandler
    private let onKey: KeyHandler

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    public private(set) var isRunning = false

    /// Events seen while armed. Zero after a failed capture attempt means the
    /// tap never saw the keyboard at all, rather than the key being rejected.
    public private(set) var eventCount = 0

    public init(
        onModifiers: @escaping ModifiersHandler,
        onKey: @escaping KeyHandler
    ) {
        self.onModifiers = onModifiers
        self.onKey = onKey
    }

    deinit {
        stop()
    }

    public func start() throws {
        guard !isRunning else { throw CaptureError.alreadyRunning }
        guard activeKeyCapture == nil else { throw CaptureError.alreadyRunning }

        let mask: CGEventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        activeKeyCapture = self

        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: magicBindKeyCaptureCallback,
                userInfo: nil
            )
        else {
            activeKeyCapture = nil
            throw CaptureError.tapCreationFailed
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        // Common modes so capture keeps working while menus or a window drag
        // are tracking.
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.runLoopSource = source
        eventCount = 0
        isRunning = true
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false

        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil

        if activeKeyCapture === self {
            activeKeyCapture = nil
        }
    }

    fileprivate func reenable() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    fileprivate func deliverModifiers(_ modifiers: ShortcutModifiers) {
        eventCount += 1
        onModifiers(modifiers)
    }

    fileprivate func deliverKey(_ keyCode: UInt16, _ modifiers: ShortcutModifiers) {
        eventCount += 1
        onKey(keyCode, modifiers)
        // Deferred so the matching key-up is still swallowed by this tap rather
        // than leaking to whatever is frontmost.
        DispatchQueue.main.async { [weak self] in
            self?.stop()
        }
    }
}
