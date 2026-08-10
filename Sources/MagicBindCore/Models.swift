import Foundation

/// The kind of gesture the recognizer classified, independent of how many
/// fingers produced it.
public enum GestureKind: String, Codable, CaseIterable, Sendable {
    case tap
    case doubleTap
    case click
    case hold
    case swipeUp
    case swipeDown
    case swipeLeft
    case swipeRight

    /// A short human-readable label for the preferences UI.
    public var displayName: String {
        switch self {
        case .tap: return "Tap"
        case .doubleTap: return "Double Tap"
        case .click: return "Click"
        case .hold: return "Hold"
        case .swipeUp: return "Swipe Up"
        case .swipeDown: return "Swipe Down"
        case .swipeLeft: return "Swipe Left"
        case .swipeRight: return "Swipe Right"
        }
    }

    /// Whether recognizing this gesture needs physical mouse button events,
    /// which only arrive when `AppConfig.mouseClicksEnabled` is on.
    public var requiresMouseButtons: Bool {
        self == .click
    }

    /// Whether this gesture is a directional swipe.
    public var isSwipe: Bool {
        switch self {
        case .swipeUp, .swipeDown, .swipeLeft, .swipeRight: return true
        default: return false
        }
    }

    /// An SF Symbol suggesting the motion, for the bindings UI.
    public var symbolName: String {
        switch self {
        case .tap: return "hand.tap"
        case .doubleTap: return "hand.tap.fill"
        case .click: return "cursorarrow.click"
        case .hold: return "hand.raised"
        case .swipeUp: return "arrow.up"
        case .swipeDown: return "arrow.down"
        case .swipeLeft: return "arrow.left"
        case .swipeRight: return "arrow.right"
        }
    }
}

/// A physical mouse button, as reported by the event tap.
public enum MouseButton: Int, Codable, CaseIterable, Sendable {
    case left = 0
    case right = 1
    case middle = 2

    public var displayName: String {
        switch self {
        case .left: return "Left Button"
        case .right: return "Right Button"
        case .middle: return "Middle Button"
        }
    }
}

/// A fully-qualified gesture: "three-finger tap", "four-finger swipe up".
///
/// This is both what `GestureRecognizer` emits and what a `GestureBinding`
/// matches on, which is why it is `Hashable` — bindings are looked up by
/// spec.
public struct GestureSpec: Codable, Hashable, Sendable {
    public var fingerCount: Int
    public var kind: GestureKind

    /// Which physical button, for `.click` gestures. `nil` for everything else.
    ///
    /// Optional so configs written before click support existed still decode.
    public var button: MouseButton?

    public init(fingerCount: Int, kind: GestureKind, button: MouseButton? = nil) {
        self.fingerCount = fingerCount
        self.kind = kind
        // Normalizing here keeps lookup honest: a tap that carried a stray
        // button value would never match the tap the recognizer emits.
        self.button = kind == .click ? (button ?? .left) : nil
    }

    /// e.g. "3-finger Tap", "2-finger Left Button Click", "Right Button Click"
    public var displayName: String {
        let fingers = fingerCount == 0 ? "" : "\(fingerCount)-finger "
        guard kind == .click, let button else {
            return fingers + kind.displayName
        }
        return "\(fingers)\(button.displayName) Click"
    }
}

/// What a bound gesture actually does.
public enum ActionType: String, Codable, CaseIterable, Sendable {
    case middleClick
    case keyboardShortcut
    /// One of the named system actions in `PresetAction` — Mission Control,
    /// Screen Capture, Volume Up and so on.
    case preset
    case launchApp
    case shellCommand
    case appleScript

    public var displayName: String {
        switch self {
        case .middleClick: return "Middle Click"
        case .keyboardShortcut: return "Keyboard Shortcut"
        case .preset: return "System Action"
        case .launchApp: return "Launch App"
        case .shellCommand: return "Shell Command"
        case .appleScript: return "AppleScript"
        }
    }

    public var symbolName: String {
        switch self {
        case .middleClick: return "cursorarrow.click.2"
        case .keyboardShortcut: return "keyboard"
        case .preset: return "sparkles"
        case .launchApp: return "app.badge"
        case .shellCommand: return "terminal"
        case .appleScript: return "scroll"
        }
    }
}

/// The parameters for an action. Which fields are meaningful depends on
/// `type`; the rest are ignored.
///
/// This is deliberately one flat struct rather than an enum with associated
/// values, because it round-trips to hand-editable JSON and a flat shape is
/// far kinder to someone editing `config.json` in a text editor.
public struct ActionConfig: Codable, Hashable, Sendable {
    public var type: ActionType

    /// Which named system action, for `.preset`.
    public var preset: PresetAction?

    /// Virtual key code for `.keyboardShortcut` (e.g. 21 is "4" on US ANSI).
    public var keyCode: UInt16?

    /// Modifier flags for `.keyboardShortcut`, as the raw value of
    /// `CGEventFlags` — kept as a plain integer so the model stays free of
    /// CoreGraphics.
    public var modifiers: UInt64?

    /// Bundle identifier for `.launchApp`, e.g. "com.apple.Safari".
    public var bundleIdentifier: String?

    /// Command line for `.shellCommand`, run via `/bin/sh -c`.
    public var command: String?

    /// Source text for `.appleScript`.
    public var script: String?

    public init(
        type: ActionType,
        preset: PresetAction? = nil,
        keyCode: UInt16? = nil,
        modifiers: UInt64? = nil,
        bundleIdentifier: String? = nil,
        command: String? = nil,
        script: String? = nil
    ) {
        self.type = type
        self.preset = preset
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.bundleIdentifier = bundleIdentifier
        self.command = command
        self.script = script
    }
}

/// One gesture mapped to one action.
public struct GestureBinding: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var gesture: GestureSpec
    public var action: ActionConfig
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        gesture: GestureSpec,
        action: ActionConfig,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.gesture = gesture
        self.action = action
        self.isEnabled = isEnabled
    }
}

/// Tuning constants for `GestureRecognizer`.
///
/// - Important: These defaults are untested guesses. They need real-device
///   calibration — that is the entire point of Phase 2/3 in `ProjectPlan.md`.
///   They live in the config so they can be tuned without a rebuild.
public struct RecognizerTuning: Codable, Hashable, Sendable {
    /// Longest contact that can still count as a tap, in seconds.
    public var tapMaxDuration: Double

    /// Largest centroid travel that still counts as a tap, in normalized units.
    public var tapMaxMovement: Double

    /// Centroid travel required before a swipe fires, in normalized units.
    public var swipeMinMovement: Double

    /// Contact duration required before a hold fires, in seconds.
    public var holdMinDuration: Double

    /// Largest centroid travel a hold tolerates, in normalized units.
    public var holdMaxMovement: Double

    /// Longest gap between two taps that still counts as a double tap, in
    /// seconds. Optional so older configs decode; falls back to the default.
    public var doubleTapMaxInterval: Double?

    /// The effective double-tap window.
    public var effectiveDoubleTapMaxInterval: Double {
        doubleTapMaxInterval ?? 0.35
    }

    public init(
        tapMaxDuration: Double = 0.25,
        tapMaxMovement: Double = 0.03,
        swipeMinMovement: Double = 0.08,
        holdMinDuration: Double = 0.5,
        holdMaxMovement: Double = 0.03,
        doubleTapMaxInterval: Double? = 0.35
    ) {
        self.tapMaxDuration = tapMaxDuration
        self.tapMaxMovement = tapMaxMovement
        self.swipeMinMovement = swipeMinMovement
        self.holdMinDuration = holdMinDuration
        self.holdMaxMovement = holdMaxMovement
        self.doubleTapMaxInterval = doubleTapMaxInterval
    }

    public static let `default` = RecognizerTuning()
}

/// The whole persisted configuration.
public struct AppConfig: Codable, Hashable, Sendable {
    /// Schema version, so `ConfigStore` can migrate older files.
    public var version: Int

    /// Whether the gesture engine is currently running.
    public var isEnabled: Bool

    /// Whether MagicBind watches physical mouse buttons, which is what makes
    /// `.click` gestures possible.
    ///
    /// Off by default and opt-in, because it requires a passive `CGEvent` tap —
    /// the app observes button events rather than only posting them. See
    /// SECURITY.md. Optional so pre-click configs decode unchanged.
    public var mouseClicksEnabled: Bool?

    /// The effective click-watching setting.
    public var isMouseClicksEnabled: Bool {
        mouseClicksEnabled ?? false
    }

    public var tuning: RecognizerTuning

    public var bindings: [GestureBinding]

    public static let currentVersion = 1

    public init(
        version: Int = AppConfig.currentVersion,
        isEnabled: Bool = true,
        mouseClicksEnabled: Bool? = false,
        tuning: RecognizerTuning = .default,
        bindings: [GestureBinding] = []
    ) {
        self.version = version
        self.isEnabled = isEnabled
        self.mouseClicksEnabled = mouseClicksEnabled
        self.tuning = tuning
        self.bindings = bindings
    }

    /// Looks up the first enabled binding matching a recognized gesture.
    public func binding(for gesture: GestureSpec) -> GestureBinding? {
        bindings.first { $0.isEnabled && $0.gesture == gesture }
    }
}
