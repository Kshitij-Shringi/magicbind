import MagicBindCore
import SwiftUI

/// Editor for a single binding: which gesture, and what it does.
///
/// Keyboard shortcuts are still entered as raw virtual key codes here — a
/// live "press a key to record" control is Phase 4 work, and a good first
/// contribution.
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
                    OptionalIntField(
                        label: "Key code",
                        value: $binding.action.keyCode,
                        help: "Virtual key code, e.g. 21 is \"4\" on a US ANSI layout."
                    )
                    OptionalIntField(
                        label: "Modifiers",
                        value: $binding.action.modifiers,
                        help: "CGEventFlags raw value. Command is 1048576, Shift is 131072."
                    )

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

/// A numeric field bound to an optional integer of any width.
struct OptionalIntField<Value: FixedWidthInteger>: View {
    let label: String
    @Binding var value: Value?
    var help: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            TextField(
                label,
                text: Binding(
                    get: { value.map(String.init) ?? "" },
                    set: { value = $0.isEmpty ? nil : Value($0) }
                ),
                prompt: Text("none")
            )
            if let help {
                Text(help)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
