import AppKit
import MagicBindCore

/// Starts and stops the gesture engine around the app lifecycle.
///
/// This lives in a delegate rather than in a SwiftUI `.task` because the only
/// always-present view in a menu-bar-only app is the status item label, and
/// hanging startup off its rendering is a fragile place for it.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppState.shared.startEngine()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppState.shared.stopEngine()
    }
}
