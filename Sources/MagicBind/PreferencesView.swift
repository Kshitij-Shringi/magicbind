import MagicBindCore
import SwiftUI

/// The preferences window: a list of bindings, an editor for the selected one,
/// and the recognizer tuning constants.
struct PreferencesView: View {
    @EnvironmentObject private var state: AppState
    @State private var selection: GestureBinding.ID?

    var body: some View {
        VStack(spacing: 0) {
            statusBar
            Divider()
            TabView {
                bindingsTab
                    .tabItem { Label("Bindings", systemImage: "hand.tap") }
                tuningTab
                    .tabItem { Label("Tuning", systemImage: "slider.horizontal.3") }
            }
            .padding(12)
        }
    }

    // MARK: - Status

    private var statusBar: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(state.isEngineRunning ? Color.green : Color.secondary)
                .frame(width: 8, height: 8)

            Text(state.isEngineRunning ? "Listening for gestures" : "Not running")
                .font(.subheadline)

            if let gesture = state.lastGesture {
                Text("Last: \(gesture.displayName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("Enabled", isOn: $state.config.isEnabled)
                .toggleStyle(.switch)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            if let message = state.lastErrorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
    }

    // MARK: - Bindings

    private var bindingsTab: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach($state.config.bindings) { $binding in
                        BindingRow(binding: binding)
                            .tag(binding.id)
                    }
                    .onDelete { state.deleteBindings(at: $0) }
                }
                .listStyle(.inset)

                HStack(spacing: 4) {
                    Button {
                        state.addBinding()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("Add a binding")

                    Button {
                        guard
                            let selection,
                            let index = state.config.bindings.firstIndex(where: {
                                $0.id == selection
                            })
                        else { return }
                        state.deleteBindings(at: IndexSet(integer: index))
                    } label: {
                        Image(systemName: "minus")
                    }
                    .disabled(selection == nil)
                    .help("Remove the selected binding")

                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(6)
            }
            .frame(minWidth: 220)

            Group {
                if let index = selectedIndex {
                    BindingEditView(binding: $state.config.bindings[index])
                        // Tie the editor's identity to the binding so switching
                        // selection tears it down and rebuilds it. Without this
                        // SwiftUI reuses the view, and an in-progress shortcut
                        // recording would capture into the newly selected
                        // binding instead of being cancelled.
                        .id(state.config.bindings[index].id)
                } else {
                    ContentUnavailableMessage(
                        title: "No Binding Selected",
                        message: "Pick a binding on the left, or add one with +."
                    )
                }
            }
            .frame(minWidth: 280)
        }
    }

    private var selectedIndex: Int? {
        guard let selection else { return nil }
        return state.config.bindings.firstIndex { $0.id == selection }
    }

    // MARK: - Tuning

    private var tuningTab: some View {
        Form {
            Section {
                TuningSlider(
                    label: "Tap max duration",
                    value: $state.config.tuning.tapMaxDuration,
                    range: 0.05...1.0,
                    unit: "s"
                )
                TuningSlider(
                    label: "Tap max movement",
                    value: $state.config.tuning.tapMaxMovement,
                    range: 0.005...0.2,
                    unit: ""
                )
                TuningSlider(
                    label: "Swipe min movement",
                    value: $state.config.tuning.swipeMinMovement,
                    range: 0.02...0.5,
                    unit: ""
                )
                TuningSlider(
                    label: "Hold min duration",
                    value: $state.config.tuning.holdMinDuration,
                    range: 0.1...2.0,
                    unit: "s"
                )
                TuningSlider(
                    label: "Hold max movement",
                    value: $state.config.tuning.holdMaxMovement,
                    range: 0.005...0.2,
                    unit: ""
                )
            } header: {
                Text("Recognizer thresholds")
            } footer: {
                Text(
                    """
                    These defaults are untested guesses and need calibration \
                    against a real device. Movement is in normalized units, \
                    where 1.0 spans the whole touch surface.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Text(state.configPath)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.head)
                    Spacer()
                    Button("Reset to Defaults") {
                        state.resetToDefaults()
                    }
                }
            } header: {
                Text("Config file")
            }
        }
        .formStyle(.grouped)
    }
}

/// One row in the bindings list.
struct BindingRow: View {
    let binding: GestureBinding

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(binding.gesture.displayName)
                Text(binding.action.displaySummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if !binding.isEnabled {
                Image(systemName: "pause.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// A labelled slider with a numeric readout, used for every tuning constant.
struct TuningSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let unit: String

    var body: some View {
        HStack {
            Text(label)
            Slider(value: $value, in: range)
            Text(String(format: "%.3f%@", value, unit))
                .font(.caption.monospacedDigit())
                .frame(width: 60, alignment: .trailing)
        }
    }
}

/// A small placeholder. `ContentUnavailableView` is macOS 14+, and this app
/// still supports macOS 13.
struct ContentUnavailableMessage: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
