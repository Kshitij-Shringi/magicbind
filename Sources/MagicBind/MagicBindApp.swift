import AppKit
import MagicBindCore
import SwiftUI

/// Menu-bar-only entry point. `LSUIElement` in `Resources/Info.plist` keeps it
/// out of the Dock, so the menu bar item is the whole UI surface until the
/// preferences window is opened.
@main
struct MagicBindApp: App {
    @StateObject private var state = AppState.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("MagicBind", systemImage: "cursorarrow.click.2") {
            MenuBarContent()
                .environmentObject(state)
        }

        Window("MagicBind Preferences", id: WindowID.preferences) {
            PreferencesView()
                .environmentObject(state)
                .frame(minWidth: 560, minHeight: 420)
        }
        .windowResizability(.contentMinSize)
    }
}

enum WindowID {
    static let preferences = "preferences"
}

/// The menu bar dropdown.
struct MenuBarContent: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(state.config.isEnabled ? "Disable Gestures" : "Enable Gestures") {
            state.toggleEnabled()
        }

        Divider()

        Button("Preferences…") {
            openWindow(id: WindowID.preferences)
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Quit MagicBind") {
            state.stopEngine()
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
