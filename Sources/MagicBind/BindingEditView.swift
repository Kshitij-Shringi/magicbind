import MagicBindCore
import SwiftUI

/// Editor for a single binding: which gesture, and what it does.
///
/// Keyboard shortcuts are captured live by `ShortcutRecorderView` rather than
/// typed as virtual key codes.
struct BindingEditView: View {
    @Binding var binding: GestureBinding

    var body: some View {
        Form {
            Section("Gesture") {
                Picker("Fingers", selection: $binding.gesture.fingerCount) {
                    ForEach(1...5, id: \.self) { count in
                        Text("\(count)").tag(count)
                    }
                }

                Picker("Motion", selection: $binding.gesture.kind) {
                    ForEach(GestureKind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }

                Toggle("Enabled", isOn: $binding.isEnabled)
            }

            Section("Action") {
                Picker("Type", selection: $binding.action.type) {
                    ForEach(ActionType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }

                switch binding.action.type {
                case .middleClick:
                    Text("Posts a middle mouse button click at the pointer.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                case .keyboardShortcut:
                    LabeledContent("Shortcut") {
                        ShortcutRecorderView(
                            keyCode: $binding.action.keyCode,
                            modifiers: $binding.action.modifiers
                        )
                    }

                case .launchApp:
                    OptionalTextField(
                        label: "Bundle ID",
                        value: $binding.action.bundleIdentifier,
                        prompt: "com.apple.Safari"
                    )

                case .shellCommand:
                    OptionalTextField(
                        label: "Command",
                        value: $binding.action.command,
                        prompt: "open -a Terminal"
                    )

                case .appleScript:
                    OptionalTextField(
                        label: "Script",
                        value: $binding.action.script,
                        prompt: "display notification \"hi\"",
                        axis: .vertical
                    )
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// A text field bound to an optional string, treating empty as `nil` so the
/// JSON stays clean.
struct OptionalTextField: View {
    let label: String
    @Binding var value: String?
    var prompt: String = ""
    var axis: Axis = .horizontal

    var body: some View {
        TextField(
            label,
            text: Binding(
                get: { value ?? "" },
                set: { value = $0.isEmpty ? nil : $0 }
            ),
            prompt: Text(prompt),
            axis: axis
        )
        .lineLimit(axis == .vertical ? 3...8 : 1...1)
    }
}
