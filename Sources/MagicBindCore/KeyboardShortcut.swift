import Carbon.HIToolbox
import Foundation

/// The modifier keys a keyboard-shortcut action can carry.
///
/// Raw values are deliberately identical to `CGEventFlags`, because that is
/// what `ActionConfig.modifiers` stores and what `ActionExecutor` posts. Keeping
/// them in one option set means the UI, the JSON, and the event posting all
/// agree without conversion tables scattered around.
public struct ShortcutModifiers: OptionSet, Hashable, Sendable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }

    public static let capsLock = ShortcutModifiers(rawValue: 0x0001_0000)
    public static let shift = ShortcutModifiers(rawValue: 0x0002_0000)
    public static let control = ShortcutModifiers(rawValue: 0x0004_0000)
    public static let option = ShortcutModifiers(rawValue: 0x0008_0000)
    public static let command = ShortcutModifiers(rawValue: 0x0010_0000)
    public static let numericPad = ShortcutModifiers(rawValue: 0x0020_0000)
    public static let help = ShortcutModifiers(rawValue: 0x0040_0000)
    public static let function = ShortcutModifiers(rawValue: 0x0080_0000)

    /// The modifiers worth showing to the user and worth persisting. Notably
    /// excludes `numericPad`, which the system sets on arrow keys and the
    /// keypad as a side effect rather than as something the user held.
    public static let displayable: ShortcutModifiers = [
        .capsLock, .control, .option, .shift, .command, .function
    ]

    /// The glyph string for these modifiers, in the order Apple uses in menus:
    /// fn, ⇪, ⌃, ⌥, ⇧, ⌘.
    public var glyphs: String {
        var result = ""
        if contains(.function) { result += "fn" }
        if contains(.capsLock) { result += "⇪" }
        if contains(.control) { result += "⌃" }
        if contains(.option) { result += "⌥" }
        if contains(.shift) { result += "⇧" }
        if contains(.command) { result += "⌘" }
        return result
    }
}

/// Renders a virtual key code and modifier set as the shortcut string a person
/// would recognize — "⇧⌘4", "⌃␣", "F5".
///
/// Key labels are resolved against the user's *current keyboard layout* rather
/// than a hardcoded US table, so an AZERTY or Dvorak user sees the key they
/// actually pressed.
public enum KeyboardShortcutFormatter {
    /// Keys whose label is a glyph or a name rather than a character they type.
    /// These are layout-independent, so they're resolved before consulting the
    /// keyboard layout.
    private static let specialKeyLabels: [UInt16: String] = [
        UInt16(kVK_Return): "↩",
        UInt16(kVK_Tab): "⇥",
        UInt16(kVK_Space): "␣",
        UInt16(kVK_Delete): "⌫",
        UInt16(kVK_ForwardDelete): "⌦",
        UInt16(kVK_Escape): "⎋",
        UInt16(kVK_ANSI_KeypadEnter): "⌤",
        UInt16(kVK_ANSI_KeypadClear): "⌧",
        UInt16(kVK_Home): "↖",
        UInt16(kVK_End): "↘",
        UInt16(kVK_PageUp): "⇞",
        UInt16(kVK_PageDown): "⇟",
        UInt16(kVK_LeftArrow): "←",
        UInt16(kVK_RightArrow): "→",
        UInt16(kVK_UpArrow): "↑",
        UInt16(kVK_DownArrow): "↓",
        UInt16(kVK_Help): "?⃝",
        UInt16(kVK_F1): "F1",
        UInt16(kVK_F2): "F2",
        UInt16(kVK_F3): "F3",
        UInt16(kVK_F4): "F4",
        UInt16(kVK_F5): "F5",
        UInt16(kVK_F6): "F6",
        UInt16(kVK_F7): "F7",
        UInt16(kVK_F8): "F8",
        UInt16(kVK_F9): "F9",
        UInt16(kVK_F10): "F10",
        UInt16(kVK_F11): "F11",
        UInt16(kVK_F12): "F12",
        UInt16(kVK_F13): "F13",
        UInt16(kVK_F14): "F14",
        UInt16(kVK_F15): "F15",
        UInt16(kVK_F16): "F16",
        UInt16(kVK_F17): "F17",
        UInt16(kVK_F18): "F18",
        UInt16(kVK_F19): "F19",
        UInt16(kVK_F20): "F20"
    ]

    /// The full shortcut string, or `nil` if no key has been recorded.
    public static func displayString(keyCode: UInt16?, modifiers: UInt64?) -> String? {
        guard let keyCode else { return nil }
        let flags = ShortcutModifiers(rawValue: modifiers ?? 0)
            .intersection(.displayable)
        return flags.glyphs + keyLabel(for: keyCode)
    }

    /// The label for a single key, without modifiers.
    public static func keyLabel(for keyCode: UInt16) -> String {
        if let special = specialKeyLabels[keyCode] {
            return special
        }
        if let character = layoutCharacter(for: keyCode) {
            return character.uppercased()
        }
        // An unmapped key still needs to render as *something* recognizable,
        // and the raw code is at least actionable when reporting a bug.
        return "Key \(keyCode)"
    }

    /// Asks the current keyboard layout what character a key code produces with
    /// no modifiers held.
    private static func layoutCharacter(for keyCode: UInt16) -> String? {
        guard let layoutData = currentLayoutData() else { return nil }

        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0

        let status = layoutData.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self)
            else {
                return OSStatus(paramErr)
            }
            return UCKeyTranslate(
                layout,
                keyCode,
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                characters.count,
                &length,
                &characters
            )
        }

        guard status == noErr, length > 0 else { return nil }

        let string = String(utf16CodeUnits: characters, count: length)
        return string.isEmpty ? nil : string
    }

    /// The Unicode layout data for the current input source.
    ///
    /// Some input sources (many IMEs) carry no Unicode layout, so this falls
    /// back to the current ASCII-capable layout before giving up.
    private static func currentLayoutData() -> Data? {
        let sources = [
            TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue()
        ]

        for source in sources.compactMap({ $0 }) {
            guard
                let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
            else { continue }
            let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
            if !data.isEmpty { return data }
        }
        return nil
    }
}

public extension ActionConfig {
    /// The bound shortcut rendered for display, or `nil` if none is set.
    ///
    /// Meaningful only when `type` is `.keyboardShortcut`.
    var shortcutDisplayString: String? {
        KeyboardShortcutFormatter.displayString(keyCode: keyCode, modifiers: modifiers)
    }

    /// A one-line summary for the bindings list: the action type, plus the
    /// detail that distinguishes two bindings of the same type.
    var displaySummary: String {
        switch type {
        case .middleClick:
            return type.displayName
        case .keyboardShortcut:
            return "\(type.displayName) · \(shortcutDisplayString ?? "not set")"
        case .preset:
            guard let preset else { return "\(type.displayName) · not set" }
            guard let shortcut = preset.shortcutDisplayString else { return preset.displayName }
            return "\(preset.displayName) · \(shortcut)"
        case .launchApp:
            return "\(type.displayName) · \(bundleIdentifier ?? "not set")"
        case .shellCommand:
            return "\(type.displayName) · \(command ?? "not set")"
        case .appleScript:
            return type.displayName
        }
    }
}
