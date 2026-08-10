import Foundation

/// The named system actions offered in the Actions panel, so people don't have
/// to know that "Mission Control" means ⌃↑.
///
/// Most presets are just a keyboard shortcut with a friendly name, resolved by
/// `shortcut`. The three volume presets are different: macOS exposes those as
/// system-defined media key events rather than key codes, so `shortcut` is nil
/// for them and `ActionExecutor` handles them separately.
public enum PresetAction: String, Codable, CaseIterable, Sendable {
    // Window and space management
    case missionControl
    case applicationWindows
    case showDesktop
    case desktopLeft
    case desktopRight
    case fullScreen
    case switchApplication
    case lockScreen

    // Capture
    case screenCapture
    case screenCaptureRegion

    // Editing
    case copy
    case paste
    case cut
    case undo
    case redo

    // Navigation
    case back
    case forward

    // Media
    case volumeUp
    case volumeDown
    case mute

    public var displayName: String {
        switch self {
        case .missionControl: return "Mission Control"
        case .applicationWindows: return "Application Windows"
        case .showDesktop: return "Show/Hide Desktop"
        case .desktopLeft: return "Desktop Left"
        case .desktopRight: return "Desktop Right"
        case .fullScreen: return "Maximize Window"
        case .switchApplication: return "Switch Application"
        case .lockScreen: return "Lock Screen"
        case .screenCapture: return "Screen Capture"
        case .screenCaptureRegion: return "Capture Region"
        case .copy: return "Copy"
        case .paste: return "Paste"
        case .cut: return "Cut"
        case .undo: return "Undo"
        case .redo: return "Redo"
        case .back: return "Back"
        case .forward: return "Forward"
        case .volumeUp: return "Volume Up"
        case .volumeDown: return "Volume Down"
        case .mute: return "Mute"
        }
    }

    public var symbolName: String {
        switch self {
        case .missionControl: return "square.grid.3x3"
        case .applicationWindows: return "macwindow.on.rectangle"
        case .showDesktop: return "menubar.dock.rectangle"
        case .desktopLeft: return "arrow.left.square"
        case .desktopRight: return "arrow.right.square"
        case .fullScreen: return "arrow.up.left.and.arrow.down.right"
        case .switchApplication: return "square.on.square"
        case .lockScreen: return "lock"
        case .screenCapture: return "camera.viewfinder"
        case .screenCaptureRegion: return "crop"
        case .copy: return "doc.on.doc"
        case .paste: return "clipboard"
        case .cut: return "scissors"
        case .undo: return "arrow.uturn.backward"
        case .redo: return "arrow.uturn.forward"
        case .back: return "chevron.left"
        case .forward: return "chevron.right"
        case .volumeUp: return "speaker.wave.3"
        case .volumeDown: return "speaker.wave.1"
        case .mute: return "speaker.slash"
        }
    }

    /// The media key code for the three volume presets, using the values from
    /// IOKit's `ev_keymap.h` (`NX_KEYTYPE_*`). `nil` for keyboard-shortcut
    /// presets.
    public var mediaKey: Int32? {
        switch self {
        case .volumeUp: return 0      // NX_KEYTYPE_SOUND_UP
        case .volumeDown: return 1    // NX_KEYTYPE_SOUND_DOWN
        case .mute: return 7          // NX_KEYTYPE_MUTE
        default: return nil
        }
    }

    /// The keyboard shortcut this preset sends, or `nil` if it's a media key.
    ///
    /// Key codes assume the physical positions of a US ANSI layout, which is
    /// what virtual key codes describe — they are positional, not character
    /// based, so ⌘C stays on the same physical key across layouts.
    public var shortcut: (keyCode: UInt16, modifiers: ShortcutModifiers)? {
        switch self {
        case .missionControl:
            return (126, [.control])                  // ⌃↑
        case .applicationWindows:
            return (125, [.control])                  // ⌃↓
        case .showDesktop:
            return (103, [.function])                 // fn F11
        case .desktopLeft:
            return (123, [.control])                  // ⌃←
        case .desktopRight:
            return (124, [.control])                  // ⌃→
        case .fullScreen:
            return (3, [.control, .command])          // ⌃⌘F
        case .switchApplication:
            return (48, [.command])                   // ⌘⇥
        case .lockScreen:
            return (12, [.control, .command])         // ⌃⌘Q
        case .screenCapture:
            return (23, [.command, .shift])           // ⌘⇧5
        case .screenCaptureRegion:
            return (21, [.command, .shift])           // ⌘⇧4
        case .copy:
            return (8, [.command])                    // ⌘C
        case .paste:
            return (9, [.command])                    // ⌘V
        case .cut:
            return (7, [.command])                    // ⌘X
        case .undo:
            return (6, [.command])                    // ⌘Z
        case .redo:
            return (6, [.command, .shift])            // ⌘⇧Z
        case .back:
            return (33, [.command])                   // ⌘[
        case .forward:
            return (30, [.command])                   // ⌘]
        case .volumeUp, .volumeDown, .mute:
            return nil
        }
    }

    /// The shortcut rendered for display, e.g. "⌃↑" for Mission Control.
    public var shortcutDisplayString: String? {
        guard let shortcut else { return nil }
        return KeyboardShortcutFormatter.displayString(
            keyCode: shortcut.keyCode,
            modifiers: shortcut.modifiers.rawValue
        )
    }

    /// The `ActionConfig` that runs this preset.
    public var actionConfig: ActionConfig {
        ActionConfig(type: .preset, preset: self)
    }
}
