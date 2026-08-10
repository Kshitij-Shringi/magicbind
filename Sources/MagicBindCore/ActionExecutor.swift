import AppKit
import CoreGraphics
import Foundation

/// Fires the action bound to a recognized gesture.
///
/// Everything here posts synthetic input or launches something on the user's
/// behalf, which is why the app needs Accessibility permission. Nothing here
/// reads user input, records it, or sends anything off the machine.
public final class ActionExecutor {
    public enum ExecutionError: Error, LocalizedError {
        case accessibilityNotTrusted
        case eventCreationFailed
        case missingParameter(String)
        case appNotFound(String)
        case appleScriptFailed(String)

        public var errorDescription: String? {
            switch self {
            case .accessibilityNotTrusted:
                return """
                    MagicBind needs Accessibility permission to post clicks and \
                    keystrokes. Grant it in System Settings > Privacy & Security \
                    > Accessibility, then relaunch.
                    """
            case .eventCreationFailed:
                return "The system refused to create a synthetic input event."
            case .missingParameter(let name):
                return "This action needs a \(name), but none is configured."
            case .appNotFound(let identifier):
                return "No installed app with bundle identifier \(identifier)."
            case .appleScriptFailed(let message):
                return "AppleScript failed: \(message)"
            }
        }
    }

    public init() {}

    /// Whether this process currently holds Accessibility permission.
    public static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompts for Accessibility permission if it hasn't been granted. macOS
    /// shows the prompt at most once per app; after that the user has to go to
    /// System Settings themselves.
    @discardableResult
    public static func requestAccessibilityPermission() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Runs an action.
    public func perform(_ action: ActionConfig) throws {
        switch action.type {
        case .middleClick:
            try postMiddleClick()
        case .keyboardShortcut:
            try postKeyboardShortcut(action)
        case .preset:
            try runPreset(action)
        case .launchApp:
            try launchApp(action)
        case .shellCommand:
            try runShellCommand(action)
        case .appleScript:
            try runAppleScript(action)
        }
    }

    /// Runs a named system action. Most are a keyboard shortcut with a friendly
    /// name; the volume presets are media keys, which take a different path.
    private func runPreset(_ action: ActionConfig) throws {
        guard let preset = action.preset else {
            throw ExecutionError.missingParameter("system action")
        }

        if let mediaKey = preset.mediaKey {
            try postMediaKey(mediaKey)
            return
        }

        guard let shortcut = preset.shortcut else {
            throw ExecutionError.missingParameter("shortcut for \(preset.displayName)")
        }

        try postKeyboardShortcut(
            ActionConfig(
                type: .keyboardShortcut,
                keyCode: shortcut.keyCode,
                modifiers: shortcut.modifiers.rawValue
            )
        )
    }

    /// Posts a volume or mute media key.
    ///
    /// These aren't virtual key codes — macOS delivers them as `systemDefined`
    /// events with the key packed into `data1`, which is why they can't reuse
    /// the keyboard path.
    private func postMediaKey(_ key: Int32) throws {
        guard Self.isAccessibilityTrusted else { throw ExecutionError.accessibilityNotTrusted }

        for isDown in [true, false] {
            let state = isDown ? 0x0A : 0x0B
            let data1 = Int((key << 16) | Int32(state << 8))

            guard
                let event = NSEvent.otherEvent(
                    with: .systemDefined,
                    location: .zero,
                    modifierFlags: [],
                    timestamp: 0,
                    windowNumber: 0,
                    context: nil,
                    subtype: 8,  // NX_SUBTYPE_AUX_CONTROL_BUTTONS
                    data1: data1,
                    data2: -1
                ),
                let cgEvent = event.cgEvent
            else {
                throw ExecutionError.eventCreationFailed
            }

            cgEvent.post(tap: .cghidEventTap)
        }
    }

    private func postMiddleClick() throws {
        guard Self.isAccessibilityTrusted else { throw ExecutionError.accessibilityNotTrusted }

        let location = CGEvent(source: nil)?.location ?? .zero
        let source = CGEventSource(stateID: .hidSystemState)

        guard
            let down = CGEvent(
                mouseEventSource: source,
                mouseType: .otherMouseDown,
                mouseCursorPosition: location,
                mouseButton: .center
            ),
            let up = CGEvent(
                mouseEventSource: source,
                mouseType: .otherMouseUp,
                mouseCursorPosition: location,
                mouseButton: .center
            )
        else {
            throw ExecutionError.eventCreationFailed
        }

        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func postKeyboardShortcut(_ action: ActionConfig) throws {
        guard Self.isAccessibilityTrusted else { throw ExecutionError.accessibilityNotTrusted }
        guard let keyCode = action.keyCode else {
            throw ExecutionError.missingParameter("key code")
        }

        let source = CGEventSource(stateID: .hidSystemState)
        guard
            let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else {
            throw ExecutionError.eventCreationFailed
        }

        if let modifiers = action.modifiers {
            let flags = CGEventFlags(rawValue: modifiers)
            down.flags = flags
            up.flags = flags
        }

        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func launchApp(_ action: ActionConfig) throws {
        guard let identifier = action.bundleIdentifier, !identifier.isEmpty else {
            throw ExecutionError.missingParameter("bundle identifier")
        }
        guard
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
        else {
            throw ExecutionError.appNotFound(identifier)
        }

        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    private func runShellCommand(_ action: ActionConfig) throws {
        guard let command = action.command, !command.isEmpty else {
            throw ExecutionError.missingParameter("command")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        try process.run()
    }

    private func runAppleScript(_ action: ActionConfig) throws {
        guard let source = action.script, !source.isEmpty else {
            throw ExecutionError.missingParameter("script")
        }

        var errorInfo: NSDictionary?
        let script = NSAppleScript(source: source)
        script?.executeAndReturnError(&errorInfo)

        if let errorInfo {
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "unknown error"
            throw ExecutionError.appleScriptFailed(message)
        }
    }
}
