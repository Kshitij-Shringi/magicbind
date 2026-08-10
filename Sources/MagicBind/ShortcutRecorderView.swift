import AppKit
import Carbon.HIToolbox
import MagicBindCore
import SwiftUI

/// A "click to record" keyboard shortcut field.
///
/// Click it, press the shortcut you want, and it stores the virtual key code
/// and modifier flags. While recording, a local `NSEvent` monitor swallows key
/// events so pressing ⌘W records the shortcut instead of closing the window.
///
/// - Escape cancels without changing anything.
/// - Delete clears the shortcut.
struct ShortcutRecorderView: View {
    @Binding var keyCode: UInt16?
    @Binding var modifiers: UInt64?

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var liveModifiers = ShortcutModifiers()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Button(action: toggleRecording) {
                    Text(fieldLabel)
                        .font(isRecording ? .body : .body.monospaced())
                        .foregroundStyle(labelColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.bordered)
                .overlay {
                    // A focus ring stand-in, so it's obvious the field is armed
                    // and waiting for a keypress.
                    if isRecording {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.accentColor, lineWidth: 2)
                    }
                }

                if keyCode != nil && !isRecording {
                    Button {
                        clear()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .help("Remove this shortcut")
                }
            }

            Text(helpText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        // PreferencesView gives the editor a stable `.id` per binding, so
        // switching selection destroys this view and this fires — which is what
        // guarantees the monitor can't outlive the binding it was recording for.
        .onDisappear(perform: stopRecording)
    }

    // MARK: - Labels

    private var fieldLabel: String {
        if isRecording {
            return liveModifiers.isEmpty ? "Press a shortcut…" : liveModifiers.glyphs + "…"
        }
        return KeyboardShortcutFormatter.displayString(keyCode: keyCode, modifiers: modifiers)
            ?? "Click to record shortcut"
    }

    private var labelColor: Color {
        if isRecording { return .primary }
        return keyCode == nil ? .secondary : .primary
    }

    private var helpText: String {
        if isRecording {
            return "Press the keys you want. Escape cancels, Delete clears."
        }
        guard let keyCode else {
            return "This action needs a shortcut before it will do anything."
        }
        let modifierValue = modifiers ?? 0
        return "Key code \(keyCode) · modifiers \(modifierValue)"
    }

    // MARK: - Recording

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        liveModifiers = []

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            // Returning nil swallows the event, which is what stops ⌘Q from
            // quitting while the user is trying to record ⌘Q.
            handle(event)
            return nil
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        isRecording = false
        liveModifiers = []
    }

    private func handle(_ event: NSEvent) {
        let flags = ShortcutModifiers(rawValue: UInt64(event.modifierFlags.rawValue))
            .intersection(.displayable)

        switch event.type {
        case .flagsChanged:
            liveModifiers = flags

        case .keyDown:
            // Escape and Delete are only control keys when pressed bare — with a
            // modifier held they're legitimate shortcuts (⌘⌫, ⌥⎋).
            if flags.isEmpty, event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
                return
            }
            if flags.isEmpty, event.keyCode == UInt16(kVK_Delete) {
                clear()
                stopRecording()
                return
            }

            keyCode = event.keyCode
            modifiers = flags.isEmpty ? nil : flags.rawValue
            stopRecording()

        default:
            break
        }
    }

    private func clear() {
        keyCode = nil
        modifiers = nil
    }
}
