import MagicBindCore
import SwiftUI

/// What the detail pane is showing.
enum Selection: Hashable {
    case binding(GestureBinding.ID)
    case devices
    case tuning
    case about
}

/// The window: a sidebar listing every binding, and a detail pane for whatever
/// is selected.
///
/// The sidebar holds the *complete* list of bindings, grouped by gesture kind.
/// An earlier design split them across two screens — taps on one, swipes on
/// another — with no indication from either that the other existed, so there was
/// no way to see everything you'd bound. One list fixes that.
struct MainWindowView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(
                    min: Metrics.sidebarMinWidth,
                    ideal: Metrics.sidebarIdealWidth
                )
        } detail: {
            detail
                .frame(minWidth: Metrics.detailMinWidth)
        }
        .navigationTitle("MagicBind")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    state.addBinding()
                } label: {
                    Label("Add Gesture", systemImage: "plus")
                }
                .help("Add a gesture")

                Button {
                    state.deleteSelectedBinding()
                } label: {
                    Label("Remove Gesture", systemImage: "minus")
                }
                .disabled(state.selectedBindingIndex == nil)
                .help("Remove the selected gesture")
            }
        }
        .safeAreaInset(edge: .bottom) {
            StatusBar()
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch state.selection {
        case .binding:
            if let index = state.selectedBindingIndex {
                BindingDetailView(bindingIndex: index)
                    // Rebuild when the selection changes so the shortcut
                    // recorder can't outlive the binding it was recording for.
                    .id(state.config.bindings[index].id)
            } else {
                EmptyDetail(
                    symbol: "hand.tap",
                    title: "No Gesture Selected",
                    message: "Pick a gesture in the sidebar, or add one with +."
                )
            }
        case .devices:
            DevicesView()
        case .tuning:
            TuningView()
        case .about:
            AboutView()
        case .none:
            EmptyDetail(
                symbol: "hand.tap",
                title: "No Gesture Selected",
                message: "Pick a gesture in the sidebar, or add one with +."
            )
        }
    }
}

/// Engine status and the last recognized gesture, pinned to the window bottom.
struct StatusBar: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        let isLive = state.isEngineRunning && state.config.isEnabled

        HStack(spacing: 8) {
            Circle()
                .fill(isLive ? Color.green : Color.secondary)
                .frame(width: 7, height: 7)

            Text(isLive ? "Listening for gestures" : "Not listening")
                .font(.caption)

            if let message = state.lastErrorMessage {
                Text("·")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(message)
            }

            Spacer()

            // The reader's pulse. Zero here while touching the device is the
            // signature of a dead reader.
            Text("frames \(state.frameCount)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(state.frameCount == 0 ? .orange : .secondary)
                .help(
                    state.frameCount == 0
                        ? """
                            No touch frames received yet. Touch the device — if \
                            this stays at 0, the reader is not working.
                            """
                        : "Touch frames received from the multitouch reader."
                )

            if let gesture = state.lastGesture {
                // The single most useful diagnostic for "is the touch data
                // working on this Mac at all" — docs/TESTING.md leans on it.
                Text(state.lastGestureDescription ?? gesture.displayName)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            Toggle("Enabled", isOn: $state.config.isEnabled)
                .toggleStyle(.switch)
                .controlSize(.mini)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.bar)
    }
}

/// Placeholder for an empty detail pane. `ContentUnavailableView` is macOS 14+
/// and this app supports macOS 13.
struct EmptyDetail: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}
