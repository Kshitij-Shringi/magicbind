import MagicBindCore
import SwiftUI

/// The sidebar: a search field, every binding grouped by gesture kind, and the
/// settings pages underneath.
struct SidebarView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        List(selection: $state.selection) {
            ForEach(state.bindingGroups) { group in
                Section("\(group.title) (\(group.bindings.count))") {
                    ForEach(group.bindings) { binding in
                        SidebarBindingRow(binding: binding)
                            .tag(Selection.binding(binding.id))
                    }
                }
            }

            if state.bindingGroups.isEmpty {
                Section {
                    Text(
                        state.sidebarSearch.isEmpty
                            ? "No gestures yet. Add one with +."
                            : "Nothing matches “\(state.sidebarSearch)”."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
            }

            Section("Settings") {
                Label("Devices", systemImage: "laptopcomputer.and.arrow.down")
                    .badge(state.enabledDeviceCount)
                    .tag(Selection.devices)
                Label("Tuning", systemImage: "slider.horizontal.3")
                    .tag(Selection.tuning)
                Label("About", systemImage: "info.circle")
                    .tag(Selection.about)
            }
        }
        .listStyle(.sidebar)
        .searchable(
            text: $state.sidebarSearch,
            placement: .sidebar,
            prompt: "Search gestures and actions"
        )
    }
}

/// One binding in the sidebar: the gesture, and what it does.
struct SidebarBindingRow: View {
    let binding: GestureBinding

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: binding.gesture.kind.symbolName)
                .foregroundStyle(binding.isEnabled ? Color.accentColor : .secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(binding.gesture.displayName)
                    .lineLimit(1)
                Text(binding.action.displaySummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)

            if !binding.isEnabled {
                Image(systemName: "pause.circle")
                    .foregroundStyle(.secondary)
                    .help("Disabled")
            }
        }
        .padding(.vertical, 2)
        .opacity(binding.isEnabled ? 1 : 0.55)
    }
}
