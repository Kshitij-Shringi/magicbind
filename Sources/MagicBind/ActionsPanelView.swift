import MagicBindCore
import SwiftUI

/// The right-hand Actions panel: search, grouped action list, radio selection,
/// and an inline editor under whichever row needs more input.
struct ActionsPanelView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            header

            if let index = state.selectedBindingIndex {
                content(bindingIndex: index)
            } else {
                emptyState
            }
        }
        .frame(width: Theme.panelWidth)
        .background(Theme.panelBackground)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Actions")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.primaryText)
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.panelHeader)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "hand.point.up.left")
                .font(.system(size: 28))
                .foregroundStyle(Theme.secondaryText)
            Text("No gesture selected")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.primaryText)
            Text("Pick a gesture around the device, or add one with +.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Content

    private func content(bindingIndex index: Int) -> some View {
        VStack(spacing: 0) {
            searchField
            Divider().overlay(Theme.hairline)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    gestureSummary(bindingIndex: index)

                    ForEach(state.filteredActionSections) { section in
                        ActionSectionView(section: section, bindingIndex: index)
                    }

                    if state.filteredActionSections.isEmpty {
                        Text("No actions match “\(state.actionSearch)”.")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.secondaryText)
                            .padding(20)
                    }
                }
                .padding(.bottom, 24)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            TextField("Search", text: $state.actionSearch)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Theme.primaryText)

            if state.actionSearch.isEmpty {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Theme.secondaryText)
            } else {
                Button {
                    state.actionSearch = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius).fill(Theme.surface)
        )
        .padding(20)
    }

    /// Which gesture is being edited, and its finger count and enabled state —
    /// the properties of the gesture rather than of the action.
    private func gestureSummary(bindingIndex index: Int) -> some View {
        let binding = state.config.bindings[index]

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: binding.gesture.kind.symbolName)
                    .foregroundStyle(Theme.accent)
                Text(binding.gesture.displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                Spacer()
                Toggle("", isOn: $state.config.bindings[index].isEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .help("Enable or disable this gesture")
            }

            GestureShapePicker(binding: $state.config.bindings[index])

            if binding.gesture.kind.requiresMouseButtons && !state.config.isMouseClicksEnabled {
                InlineWarning(
                    text: """
                        Click gestures need mouse button watching, which is off. \
                        Turn it on in Settings.
                        """
                )
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
    }
}

/// Finger count and motion pickers for the selected gesture.
struct GestureShapePicker: View {
    @Binding var binding: GestureBinding

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Fingers")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
                Picker("", selection: fingerCountBinding) {
                    // A bare click with no fingers on the surface is a real,
                    // useful binding, so zero is offered for clicks only.
                    if binding.gesture.kind == .click {
                        Text("0").tag(0)
                    }
                    ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: binding.gesture.kind == .click ? 190 : 160)
            }

            HStack {
                Text("Motion")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
                Picker("", selection: kindBinding) {
                    ForEach(GestureKind.allCases, id: \.self) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                .labelsHidden()
                .frame(width: 150)
            }

            if binding.gesture.kind == .click {
                HStack {
                    Text("Button")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                    Spacer()
                    Picker("", selection: buttonBinding) {
                        ForEach(MouseButton.allCases, id: \.self) { button in
                            Text(button.displayName).tag(button)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }
            }
        }
    }

    // GestureSpec normalizes `button` in its initializer, so every edit goes
    // back through that initializer rather than mutating fields directly.
    private var fingerCountBinding: Binding<Int> {
        Binding(
            get: { binding.gesture.fingerCount },
            set: {
                binding.gesture = GestureSpec(
                    fingerCount: $0,
                    kind: binding.gesture.kind,
                    button: binding.gesture.button
                )
            }
        )
    }

    private var kindBinding: Binding<GestureKind> {
        Binding(
            get: { binding.gesture.kind },
            set: { newKind in
                // Swipes and taps can't have zero fingers; clicks can.
                let fingers = binding.gesture.fingerCount
                let adjusted = newKind == .click ? fingers : max(1, fingers)
                binding.gesture = GestureSpec(
                    fingerCount: adjusted,
                    kind: newKind,
                    button: binding.gesture.button
                )
            }
        )
    }

    private var buttonBinding: Binding<MouseButton> {
        Binding(
            get: { binding.gesture.button ?? .left },
            set: {
                binding.gesture = GestureSpec(
                    fingerCount: binding.gesture.fingerCount,
                    kind: binding.gesture.kind,
                    button: $0
                )
            }
        )
    }
}

/// One collapsible group of action rows.
struct ActionSectionView: View {
    @EnvironmentObject private var state: AppState
    let section: ActionSection
    let bindingIndex: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                state.toggleSection(section.id, default: section.isExpandedByDefault)
            } label: {
                HStack {
                    Text(section.title.uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                        .tracking(0.6)
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                ForEach(section.templates) { template in
                    ActionRowView(template: template, bindingIndex: bindingIndex)
                }
            }

            Divider().overlay(Theme.hairline)
        }
    }

    private var isExpanded: Bool {
        state.isSectionExpanded(section.id, default: section.isExpandedByDefault)
    }
}

/// A single selectable action, with its inline editor when selected.
struct ActionRowView: View {
    @EnvironmentObject private var state: AppState
    let template: ActionTemplate
    let bindingIndex: Int

    var body: some View {
        VStack(spacing: 0) {
            Button {
                state.select(template: template)
            } label: {
                HStack(spacing: 12) {
                    RadioIndicator(isSelected: isSelected)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(template.title)
                            .font(.system(size: 13))
                            .foregroundStyle(isSelected ? Theme.onAccent : Theme.primaryText)
                        if let subtitle = template.subtitle, !isSelected {
                            Text(subtitle)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.secondaryText)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    Image(systemName: template.symbolName)
                        .font(.system(size: 12))
                        .foregroundStyle(
                            isSelected ? Theme.onAccent.opacity(0.6) : Theme.secondaryText
                        )
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isSelected ? Theme.accent : Color.clear)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isSelected, case .needsInput(let type) = template.kind {
                inlineEditor(for: type)
            }
        }
    }

    private var isSelected: Bool {
        template.matches(state.config.bindings[bindingIndex].action)
    }

    /// The editor revealed beneath a selected row that needs more input.
    @ViewBuilder
    private func inlineEditor(for type: ActionType) -> some View {
        let action = $state.config.bindings[bindingIndex].action

        VStack(alignment: .leading, spacing: 8) {
            switch type {
            case .keyboardShortcut:
                Text("Press key combination to assign shortcut (e.g. ⌘C for Copy)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                ShortcutRecorder(
                    keyCode: action.keyCode,
                    modifiers: action.modifiers
                )
                .frame(height: 34)

            case .launchApp:
                InlineTextField(
                    title: "Bundle identifier",
                    prompt: "com.apple.Safari",
                    value: action.bundleIdentifier
                )

            case .shellCommand:
                InlineTextField(
                    title: "Command, run with /bin/sh",
                    prompt: "open -a Terminal",
                    value: action.command
                )

            case .appleScript:
                InlineTextField(
                    title: "AppleScript source",
                    prompt: "display notification \"hi\"",
                    value: action.script,
                    isMultiline: true
                )

            case .middleClick, .preset:
                EmptyView()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceRaised)
    }
}
