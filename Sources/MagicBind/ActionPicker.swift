import MagicBindCore
import SwiftUI

/// Picks what a gesture does.
///
/// A menu of grouped actions plus an inline editor for the ones needing more
/// input. The searchable radio-row catalog this replaces worked, but it made the
/// detail pane enormous; a menu keeps the whole binding visible at once and the
/// catalog's grouping survives as menu sections.
struct ActionPicker: View {
    @Binding var action: ActionConfig

    var body: some View {
        Picker("Does", selection: templateSelection) {
            ForEach(ActionCatalog.sections) { section in
                Section(section.title) {
                    ForEach(section.templates) { template in
                        Label(template.title, systemImage: template.symbolName)
                            .tag(template.id)
                    }
                }
            }
        }

        switch action.type {
        case .keyboardShortcut:
            VStack(alignment: .leading, spacing: 6) {
                ShortcutRecorder(
                    keyCode: $action.keyCode,
                    modifiers: $action.modifiers
                )
                .frame(height: 32)

                Text("Click, then press the keys. Escape cancels, Delete clears.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .launchApp:
            OptionalField(
                title: "Bundle Identifier",
                prompt: "com.apple.Safari",
                value: $action.bundleIdentifier
            )

        case .shellCommand:
            OptionalField(
                title: "Command",
                prompt: "open -a Terminal",
                value: $action.command,
                help: "Run with /bin/sh -c"
            )

        case .appleScript:
            OptionalField(
                title: "Script",
                prompt: "display notification \"hi\"",
                value: $action.script,
                isMultiline: true
            )

        case .middleClick:
            Text("Posts a middle mouse button click at the pointer.")
                .font(.caption)
                .foregroundStyle(.secondary)

        case .preset:
            if let shortcut = action.preset?.shortcutDisplayString {
                LabeledContent("Sends", value: shortcut)
                    .font(.callout)
            }
        }
    }

    /// Maps the picker's template id onto the action, preserving parameters
    /// already entered so re-picking "Keyboard Shortcut" doesn't wipe the
    /// shortcut just recorded.
    private var templateSelection: Binding<String> {
        Binding(
            get: { ActionCatalog.template(matching: action)?.id ?? "" },
            set: { id in
                guard let template = ActionCatalog.allTemplates.first(where: { $0.id == id })
                else { return }

                switch template.kind {
                case .ready(let ready):
                    action = ready
                case .needsInput(let type):
                    action = action.switchingType(to: type)
                }
            }
        )
    }
}

/// A field bound to an optional string, treating empty as `nil` so unset
/// parameters stay out of the JSON.
struct OptionalField: View {
    let title: String
    let prompt: String
    @Binding var value: String?
    var help: String?
    var isMultiline: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(
                title,
                text: Binding(
                    get: { value ?? "" },
                    set: { value = $0.isEmpty ? nil : $0 }
                ),
                prompt: Text(prompt),
                axis: isMultiline ? .vertical : .horizontal
            )
            .font(isMultiline ? .caption.monospaced() : .body)
            .lineLimit(isMultiline ? 3...8 : 1...1)

            if let help {
                Text(help)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// A small inline note, either advisory or cautionary.
struct Callout<Accessory: View>: View {
    enum Style {
        case info
        case warning

        var symbol: String {
            self == .warning ? "exclamationmark.triangle.fill" : "info.circle.fill"
        }

        var tint: Color {
            self == .warning ? .orange : .secondary
        }
    }

    let style: Style
    let text: String
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: style.symbol)
                .foregroundStyle(style.tint)
                .font(.caption)
            VStack(alignment: .leading, spacing: 6) {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                accessory()
                    .controlSize(.small)
            }
        }
    }
}

extension Callout where Accessory == EmptyView {
    init(style: Style, text: String) {
        self.init(style: style, text: text) { EmptyView() }
    }
}
