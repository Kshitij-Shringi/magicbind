import MagicBindCore
import SwiftUI

/// Editor for one binding: what the gesture is, what it does, and where it runs.
///
/// Those are three separate `Form` sections on purpose. An earlier version put
/// the finger/motion pickers inside a panel titled "Actions", which mixed "which
/// gesture" with "what it does" in one place and read as one confusing blob.
struct BindingDetailView: View {
    @EnvironmentObject private var state: AppState
    let bindingIndex: Int

    var body: some View {
        Form {
            gestureSection
            actionSection
            devicesSection
        }
        .formStyle(.grouped)
        .navigationTitle(binding.gesture.displayName)
    }

    private var binding: GestureBinding {
        state.config.bindings[bindingIndex]
    }

    private var bound: Binding<GestureBinding> {
        $state.config.bindings[bindingIndex]
    }

    // MARK: - Gesture

    private var gestureSection: some View {
        Section {
            Picker("Motion", selection: kindBinding) {
                ForEach(GestureKind.allCases, id: \.self) { kind in
                    Label(kind.displayName, systemImage: kind.symbolName).tag(kind)
                }
            }

            Picker("Fingers", selection: fingerCountBinding) {
                // A bare click with nothing touching the surface is a real,
                // useful binding, so zero is offered for clicks only.
                if binding.gesture.kind == .click {
                    Text("None").tag(0)
                }
                ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
            }
            .pickerStyle(.segmented)

            if binding.gesture.kind == .click {
                Picker("Button", selection: buttonBinding) {
                    ForEach(MouseButton.allCases, id: \.self) { button in
                        Text(button.displayName).tag(button)
                    }
                }
            }

            Toggle("Enabled", isOn: bound.isEnabled)

            if binding.gesture.kind.requiresMouseButtons && !state.config.isMouseClicksEnabled {
                Callout(
                    style: .warning,
                    text: """
                        Click gestures need mouse button watching, which is \
                        currently off.
                        """
                ) {
                    Button("Turn On in Tuning") { state.selection = .tuning }
                }
            }

            if binding.gesture.kind == .doubleTap {
                Callout(
                    style: .info,
                    text: """
                        A double tap fires Tap first, then Double Tap. Bind one \
                        or the other, not both, unless you want both to run.
                        """
                )
            }
        } header: {
            Text("Gesture")
        } footer: {
            if let conflict = state.conflictDescription(forBindingAt: bindingIndex) {
                Text(conflict)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Action

    private var actionSection: some View {
        Section("Action") {
            ActionPicker(action: bound.action)
        }
    }

    // MARK: - Devices

    private var devicesSection: some View {
        Section {
            ForEach(state.knownDeviceKinds, id: \.self) { kind in
                Toggle(isOn: deviceBinding(kind)) {
                    HStack(spacing: 6) {
                        Image(systemName: kind.symbolName)
                        Text(kind.displayName)
                        if !state.config.isDeviceEnabled(kind) {
                            Text("device off")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(!state.config.isDeviceEnabled(kind))
            }
        } header: {
            Text("Runs On")
        } footer: {
            Text(
                """
                Which devices this gesture works on. A device switched off in \
                Devices overrides this.
                """
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Bindings

    // Every gesture edit goes back through GestureSpec's initializer, which
    // normalizes `button` — a tap carrying a stray button would never match the
    // tap the recognizer emits.
    private var fingerCountBinding: Binding<Int> {
        Binding(
            get: { binding.gesture.fingerCount },
            set: { newValue in
                bound.wrappedValue.gesture = GestureSpec(
                    fingerCount: newValue,
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
                // Only clicks can have zero fingers.
                let fingers = binding.gesture.fingerCount
                let adjusted = newKind == .click ? fingers : max(1, fingers)
                bound.wrappedValue.gesture = GestureSpec(
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
            set: { newButton in
                bound.wrappedValue.gesture = GestureSpec(
                    fingerCount: binding.gesture.fingerCount,
                    kind: binding.gesture.kind,
                    button: newButton
                )
            }
        )
    }

    /// `deviceKinds == nil` means "all devices", so the first time someone
    /// unchecks one it has to be expanded into an explicit set.
    private func deviceBinding(_ kind: DeviceKind) -> Binding<Bool> {
        Binding(
            get: { binding.appliesTo(kind) },
            set: { isOn in
                var kinds = binding.deviceKinds ?? Set(state.knownDeviceKinds)
                if isOn {
                    kinds.insert(kind)
                } else {
                    kinds.remove(kind)
                }
                bound.wrappedValue.deviceKinds = kinds
            }
        )
    }
}
