import Combine
import Foundation
import MagicBindCore
import SwiftUI

/// The app's single source of truth: owns the config store and the engine, and
/// republishes config changes to SwiftUI.
@MainActor
final class AppState: ObservableObject {
    /// The instance the app runs on. `AppDelegate` needs to reach the same
    /// state SwiftUI holds, and a menu-bar-only app has no view guaranteed to
    /// be alive at launch to hand it over.
    static let shared = AppState()

    /// The live config. Every mutation writes through to disk.
    @Published var config: AppConfig {
        didSet {
            guard config != oldValue else { return }
            persist()
        }
    }

    /// The most recent error, surfaced in the preferences window.
    @Published var lastErrorMessage: String?

    /// The most recently recognized gesture, so preferences can show that the
    /// pipeline is alive even before a binding matches.
    @Published var lastGesture: GestureSpec?

    @Published private(set) var isEngineRunning = false

    private let store: ConfigStore
    private let engine: GestureEngine

    init(store: ConfigStore = ConfigStore()) {
        self.store = store
        self.engine = GestureEngine(store: store)

        do {
            try store.load()
        } catch {
            // A corrupt or future-version config shouldn't stop the app from
            // launching — fall back to defaults and tell the user.
            self.lastErrorMessage = error.localizedDescription
        }
        self.config = store.config

        engine.errorHandler = { [weak self] error in
            Task { @MainActor in self?.lastErrorMessage = error.localizedDescription }
        }
        engine.gestureHandler = { [weak self] gesture in
            Task { @MainActor in self?.lastGesture = gesture }
        }
    }

    /// Requests Accessibility permission, then starts the engine.
    func startEngine() {
        guard !isEngineRunning else { return }

        if !ActionExecutor.isAccessibilityTrusted {
            ActionExecutor.requestAccessibilityPermission()
        }

        do {
            try engine.start()
            isEngineRunning = true
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func stopEngine() {
        guard isEngineRunning else { return }
        engine.stop()
        isEngineRunning = false
    }

    func toggleEnabled() {
        config.isEnabled.toggle()
    }

    func addBinding() {
        let binding = GestureBinding(
            gesture: GestureSpec(fingerCount: 2, kind: .tap),
            action: ActionConfig(type: .middleClick)
        )
        config.bindings.append(binding)
    }

    func deleteBindings(at offsets: IndexSet) {
        config.bindings.remove(atOffsets: offsets)
    }

    func resetToDefaults() {
        config = ConfigStore.defaultConfig
    }

    /// Where the config file lives, shown in preferences so people can find it
    /// to hand-edit.
    var configPath: String {
        store.fileURL.path
    }

    private func persist() {
        do {
            try store.update(config)
            engine.reloadTuning()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }
}
