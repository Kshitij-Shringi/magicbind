import MagicBindCore
import SwiftUI

/// Recognizer thresholds and the mouse-button opt-in.
struct TuningView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Form {
            Section {
                Toggle(isOn: mouseClicksBinding) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Watch physical mouse buttons")
                        Text(
                            """
                            Required for Click gestures. Installs a listen-only \
                            event tap that reads which button was pressed and \
                            nothing else. Clicks pass through untouched.
                            """
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if state.config.isMouseClicksEnabled && !state.isWatchingMouseButtons {
                    Callout(
                        style: .warning,
                        text: """
                            Not watching buttons yet — this needs Accessibility \
                            permission. Grant it in System Settings › Privacy & \
                            Security › Accessibility, then relaunch MagicBind.
                            """
                    )
                }
            } header: {
                Text("Mouse Buttons")
            }

            Section {
                Picker("Minimum fingers", selection: minimumFingersBinding) {
                    ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)

                Text(
                    """
                    Touch gestures below this are ignored. One finger resting on \
                    a mouse is just holding the mouse — setting this to 1 makes \
                    ordinary mouse movement register as holds and swipes. Clicks \
                    are unaffected.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Sensitivity")
            }

            Section {
                ThresholdSlider(
                    label: "Tap max duration",
                    value: $state.config.tuning.tapMaxDuration,
                    range: 0.05...1.0,
                    unit: "s"
                )
                ThresholdSlider(
                    label: "Tap max movement",
                    value: $state.config.tuning.tapMaxMovement,
                    range: 0.005...0.2
                )
                ThresholdSlider(
                    label: "Double tap window",
                    value: doubleTapBinding,
                    range: 0.1...0.8,
                    unit: "s"
                )
                ThresholdSlider(
                    label: "Swipe min movement",
                    value: $state.config.tuning.swipeMinMovement,
                    range: 0.02...0.5
                )
                ThresholdSlider(
                    label: "Hold min duration",
                    value: $state.config.tuning.holdMinDuration,
                    range: 0.1...2.0,
                    unit: "s"
                )
                ThresholdSlider(
                    label: "Hold max movement",
                    value: $state.config.tuning.holdMaxMovement,
                    range: 0.005...0.2
                )

                Button("Reset Thresholds") {
                    state.config.tuning = .default
                }
            } header: {
                Text("Recognizer Thresholds")
            } footer: {
                Text(
                    """
                    These defaults are estimates, not measurements. Movement is \
                    in normalized units where 1.0 spans the whole touch surface. \
                    Changes apply immediately.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Tuning")
    }

    private var mouseClicksBinding: Binding<Bool> {
        Binding(
            get: { state.config.isMouseClicksEnabled },
            set: { state.setMouseClicksEnabled($0) }
        )
    }

    private var minimumFingersBinding: Binding<Int> {
        Binding(
            get: { state.config.tuning.effectiveMinimumFingerCount },
            set: { state.config.tuning.minimumFingerCount = $0 }
        )
    }

    private var doubleTapBinding: Binding<Double> {
        Binding(
            get: { state.config.tuning.effectiveDoubleTapMaxInterval },
            set: { state.config.tuning.doubleTapMaxInterval = $0 }
        )
    }
}

/// A labelled slider with a numeric readout.
struct ThresholdSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var unit: String = ""

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .frame(width: 148, alignment: .leading)
            Slider(value: $value, in: range)
            Text(String(format: "%.3f%@", value, unit))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .trailing)
        }
    }
}
