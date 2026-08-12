import MagicBindCore
import SwiftUI

/// The Devices page: every attached multitouch device, and whether MagicBind
/// acts on gestures from it.
struct DevicesView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Form {
            Section {
                if state.detectedDevices.isEmpty {
                    Text(
                        state.isEngineRunning
                            ? "No multitouch devices detected."
                            : "Not listening yet — devices appear once the engine starts."
                    )
                    .foregroundStyle(.secondary)
                } else {
                    ForEach(state.detectedDevices) { device in
                        DeviceRow(device: device)
                    }
                }
            } header: {
                Text("Detected Devices")
            } footer: {
                Text(
                    """
                    Each device gets its own recognizer, so touches on one can't \
                    be mistaken for a gesture on another.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                ForEach(DeviceKind.allCases, id: \.self) { kind in
                    if !state.detectedKinds.contains(kind) {
                        Toggle(isOn: state.deviceEnabledBinding(kind)) {
                            HStack(spacing: 6) {
                                Image(systemName: kind.symbolName)
                                Text(kind.displayName)
                            }
                        }
                    }
                }
            } header: {
                Text("Not Currently Attached")
            } footer: {
                Text("Set these ahead of time and they apply when the device connects.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Callout(
                    style: .warning,
                    text: """
                        macOS already uses three- and four-finger trackpad \
                        gestures for Mission Control, Look Up, and drag. Enabling \
                        a trackpad here means your bindings fire *in addition to* \
                        those — MagicBind does not suppress the system gesture. \
                        Expect both to happen, and prefer finger counts macOS \
                        leaves alone.
                        """
                )
            } header: {
                Text("About Trackpads")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Devices")
    }
}

/// One detected device, with its enable switch and the values used to classify
/// it — worth quoting in a bug report if the classification looks wrong.
struct DeviceRow: View {
    @EnvironmentObject private var state: AppState
    let device: MTDeviceInfo

    var body: some View {
        Toggle(isOn: state.deviceEnabledBinding(device.kind)) {
            HStack(spacing: 8) {
                Image(systemName: device.kind.symbolName)
                    .foregroundStyle(
                        state.config.isDeviceEnabled(device.kind) ? Color.accentColor : .secondary
                    )
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(device.displayName)
                        if device.kind == .other {
                            Text("unrecognized")
                                .font(.caption2)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(
                                    Capsule().fill(Color.orange.opacity(0.2))
                                )
                        }
                    }
                    Text(device.technicalSummary)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

/// The About page: version, build, and commit, for bug reports.
struct AboutView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Form {
            Section("Version") {
                LabeledContent("MagicBind", value: state.versionSummary)
                    .textSelection(.enabled)
                Text("Include this in bug reports — see docs/TESTING.md.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Config File") {
                Text(state.configPath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Button("Reveal in Finder") { state.revealConfigInFinder() }
                    Button("Reset to Defaults") { state.resetToDefaults() }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("About")
    }
}
