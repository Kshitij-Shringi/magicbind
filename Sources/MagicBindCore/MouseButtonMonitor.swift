import CoreGraphics
import Foundation

/// The single monitor the C tap callback forwards to. `@convention(c)`
/// callbacks can't capture context, so this is how the callback finds its
/// monitor — same pattern as `MultitouchReader`.
private var activeButtonMonitor: MouseButtonMonitor?

private func magicBindMouseTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    // The system disables a tap that takes too long or that was disabled by
    // the user. Re-enabling is the documented recovery, and without it the tap
    // goes silently dead.
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        activeButtonMonitor?.reenable()
        return Unmanaged.passUnretained(event)
    }

    if let monitor = activeButtonMonitor,
       let button = MouseButton(
           rawValue: Int(event.getIntegerValueField(.mouseEventButtonNumber))
       ) {
        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            monitor.deliver(button: button, isDown: true)
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            monitor.deliver(button: button, isDown: false)
        default:
            break
        }
    }

    // Always pass the event straight through. The tap is listen-only, so normal
    // clicking is completely unaffected by MagicBind.
    return Unmanaged.passUnretained(event)
}

/// Watches physical mouse button presses so `.click` gestures can be
/// recognized.
///
/// - Important: This installs a **listen-only** `CGEvent` tap. It observes
///   button-down and button-up events and their button number, and nothing
///   else — no keystrokes, no coordinates, no event contents are read or
///   stored, and every event is passed through unmodified so clicking behaves
///   exactly as it would without MagicBind running.
///
///   Touch frames alone cannot tell you whether the user pressed the button,
///   so there is no way to recognize a click without observing button events.
///   This is why the feature is opt-in via `AppConfig.mouseClicksEnabled`, and
///   why it's disclosed in SECURITY.md.
public final class MouseButtonMonitor {
    public enum MonitorError: Error, LocalizedError {
        case tapCreationFailed
        case alreadyRunning

        public var errorDescription: String? {
            switch self {
            case .tapCreationFailed:
                return """
                    MagicBind couldn't watch mouse buttons. This needs \
                    Accessibility permission — grant it in System Settings > \
                    Privacy & Security > Accessibility, then relaunch. Click \
                    gestures won't work until then.
                    """
            case .alreadyRunning:
                return "A MouseButtonMonitor is already running."
            }
        }
    }

    /// Called on button state changes, on the run loop the monitor was started
    /// from.
    public typealias ButtonHandler = (MouseButton, Bool) -> Void

    private let handler: ButtonHandler
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    public private(set) var isRunning = false

    /// Which buttons are currently held, so the recognizer can ask rather than
    /// track it separately.
    public private(set) var pressedButtons: Set<MouseButton> = []

    public init(handler: @escaping ButtonHandler) {
        self.handler = handler
    }

    deinit {
        stop()
    }

    /// Whether a listen-only tap can be created, which is the practical test
    /// for "do we hold Accessibility permission".
    public static var isPermitted: Bool {
        CGPreflightListenEventAccess()
    }

    /// Asks the system for input-monitoring access. Shows the prompt at most
    /// once; after that the user has to visit System Settings.
    @discardableResult
    public static func requestPermission() -> Bool {
        CGRequestListenEventAccess()
    }

    public func start() throws {
        guard !isRunning else { throw MonitorError.alreadyRunning }
        guard activeButtonMonitor == nil else { throw MonitorError.alreadyRunning }

        let mask: CGEventMask =
            (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.leftMouseUp.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
            | (1 << CGEventType.rightMouseUp.rawValue)
            | (1 << CGEventType.otherMouseDown.rawValue)
            | (1 << CGEventType.otherMouseUp.rawValue)

        activeButtonMonitor = self

        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: mask,
                callback: magicBindMouseTapCallback,
                userInfo: nil
            )
        else {
            activeButtonMonitor = nil
            throw MonitorError.tapCreationFailed
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.runLoopSource = source
        isRunning = true
    }

    public func stop() {
        guard isRunning else { return }
        isRunning = false

        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        pressedButtons = []

        if activeButtonMonitor === self {
            activeButtonMonitor = nil
        }
    }

    fileprivate func reenable() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    fileprivate func deliver(button: MouseButton, isDown: Bool) {
        if isDown {
            pressedButtons.insert(button)
        } else {
            pressedButtons.remove(button)
        }
        handler(button, isDown)
    }
}
