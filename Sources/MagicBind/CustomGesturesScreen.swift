import MagicBindCore
import SwiftUI

/// The directional gesture screen: swipes arranged around the device by
/// direction, with the click gesture in the middle.
///
/// One finger count at a time, because "2-finger swipe left" and "4-finger
/// swipe left" are different bindings and showing all of them at once around a
/// compass is unreadable.
struct CustomGesturesScreen: View {
    @EnvironmentObject private var state: AppState

    private let directions: [(kind: GestureKind, symbol: String)] = [
        (.swipeUp, "arrow.up"),
        (.swipeRight, "arrow.right"),
        (.swipeDown, "arrow.down"),
        (.swipeLeft, "arrow.left")
    ]

    var body: some View {
        VStack(spacing: 14) {
            fingerCountPicker

            HStack(spacing: 18) {
                slot(for: .swipeLeft, symbol: "arrow.left")

                VStack(spacing: 12) {
                    slot(for: .swipeUp, symbol: "arrow.up")

                    DeviceIllustration(
                        fingerCount: state.gestureScreenFingerCount,
                        showsClick: true
                    )
                    .frame(width: 132, height: 258)

                    slot(for: .swipeDown, symbol: "arrow.down")
                }

                slot(for: .swipeRight, symbol: "arrow.right")
            }

            centerSlot

            Text("Pick a direction to bind it, then choose an action on the right.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var fingerCountPicker: some View {
        HStack(spacing: 10) {
            Text("Fingers")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
            Picker("", selection: $state.gestureScreenFingerCount) {
                ForEach(1...5, id: \.self) { Text("\($0)").tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 190)
        }
    }

    /// One direction: shows the bound action, or an "unassigned" placeholder
    /// that creates the binding when clicked.
    private func slot(for kind: GestureKind, symbol: String) -> some View {
        let spec = GestureSpec(
            fingerCount: state.gestureScreenFingerCount,
            kind: kind
        )
        let existing = state.binding(for: spec)

        return VStack(spacing: 5) {
            if kind == .swipeUp {
                slotChip(spec: spec, existing: existing)
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
            } else if kind == .swipeDown {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
                slotChip(spec: spec, existing: existing)
            } else {
                HStack(spacing: 6) {
                    if kind == .swipeRight {
                        Image(systemName: symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.secondaryText)
                        slotChip(spec: spec, existing: existing)
                    } else {
                        slotChip(spec: spec, existing: existing)
                        Image(systemName: symbol)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }
        }
    }

    private var centerSlot: some View {
        let spec = GestureSpec(
            fingerCount: state.gestureScreenFingerCount,
            kind: .click,
            button: .left
        )
        return VStack(spacing: 4) {
            slotChip(spec: spec, existing: state.binding(for: spec))
            Text("Click with \(state.gestureScreenFingerCount) finger(s)")
                .font(.system(size: 10))
                .foregroundStyle(Theme.secondaryText)
        }
    }

    private func slotChip(spec: GestureSpec, existing: GestureBinding?) -> some View {
        Button {
            state.selectOrCreate(spec: spec)
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(existing?.action.displaySummary ?? "Unassigned")
                    .font(.system(size: 12, weight: existing == nil ? .regular : .semibold))
                    .foregroundStyle(chipTextColor(existing: existing))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(minWidth: 120, maxWidth: 170, alignment: .leading)
            .chipBackground(isSelected: isSelected(spec: spec, existing: existing))
        }
        .buttonStyle(.plain)
    }

    private func isSelected(spec: GestureSpec, existing: GestureBinding?) -> Bool {
        guard let existing else { return false }
        return state.selectedBindingID == existing.id
    }

    private func chipTextColor(existing: GestureBinding?) -> Color {
        if isSelected(spec: GestureSpec(fingerCount: 0, kind: .tap), existing: existing) {
            return Theme.onAccent
        }
        guard let existing else { return Theme.secondaryText }
        return state.selectedBindingID == existing.id ? Theme.onAccent : Theme.primaryText
    }
}

/// Recognizer thresholds and the mouse-click opt-in.
struct TuningSettingsScreen: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                section("Mouse buttons") {
                    Toggle(isOn: mouseClicksBinding) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Watch physical mouse buttons")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.primaryText)
                            Text(
                                """
                                Required for Click gestures. Installs a \
                                listen-only event tap that reads which button \
                                was pressed and nothing else. Every click is \
                                passed through untouched.
                                """
                            )
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .toggleStyle(.switch)

                    if state.config.isMouseClicksEnabled && !state.isWatchingMouseButtons {
                        InlineWarning(
                            text: """
                                Not watching buttons yet — this needs \
                                Accessibility permission. Grant it in System \
                                Settings › Privacy & Security › Accessibility, \
                                then relaunch MagicBind.
                                """
                        )
                    }
                }

                section("Recognizer thresholds") {
                    Text(
                        """
                        These defaults are estimates, not measurements. Movement \
                        is in normalized units where 1.0 spans the whole touch \
                        surface.
                        """
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

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
                }

                section("Double tap behaviour") {
                    Text(
                        """
                        A double tap fires Tap first, then Double Tap. \
                        Suppressing the first tap would mean delaying every \
                        single tap by the double-tap window, which makes taps \
                        feel laggy — so bind one or the other, not both, unless \
                        you want both to run.
                        """
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                }

                section("Config file") {
                    Text(state.configPath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.secondaryText)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 10) {
                        Button("Reveal in Finder") { state.revealConfigInFinder() }
                        Button("Reset to Defaults") { state.resetToDefaults() }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 560, alignment: .leading)
        }
    }

    private var mouseClicksBinding: Binding<Bool> {
        Binding(
            get: { state.config.isMouseClicksEnabled },
            set: { state.setMouseClicksEnabled($0) }
        )
    }

    private var doubleTapBinding: Binding<Double> {
        Binding(
            get: { state.config.tuning.effectiveDoubleTapMaxInterval },
            set: { state.config.tuning.doubleTapMaxInterval = $0 }
        )
    }

    private func section(
        _ title: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.secondaryText)
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.cornerRadius).fill(Theme.surface.opacity(0.6))
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
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.primaryText)
                .frame(width: 150, alignment: .leading)
            Slider(value: $value, in: range)
            Text(String(format: "%.3f%@", value, unit))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 58, alignment: .trailing)
        }
    }
}
