import AppKit
import Combine
import Foundation
import MagicBindCore
import SwiftUI

/// Which screen the canvas is showing.
enum AppScreen: Hashable {
    case device
    case customGestures
    case settings

    var title: String {
        switch self {
        case .device: return "Device"
        case .customGestures: return "Custom gestures"
        case .settings: return "Settings"
        }
    }
}

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

    @Published var screen: AppScreen = .device
    @Published var selectedBindingID: GestureBinding.ID?
    @Published var actionSearch: String = ""

    /// Which finger count the Custom gestures screen is showing.
    @Published var gestureScreenFingerCount: Int = 3

    /// Section expansion in the Actions panel, keyed by section id.
    @Published private var expandedSections: [String: Bool] = [:]

    /// The most recent error, surfaced in the window footer.
    @Published var lastErrorMessage: String?

    /// The most recently recognized gesture, so the UI can show that the
    /// pipeline is alive even before a binding matches.
    @Published var lastGesture: GestureSpec?

    @Published private(set) var isEngineRunning = false
    @Published private(set) var isWatchingMouseButtons = false

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
        self.selectedBindingID = store.config.bindings.first?.id

        engine.errorHandler = { [weak self] error in
            Task { @MainActor in self?.lastErrorMessage = error.localizedDescription }
        }
        engine.gestureHandler = { [weak self] gesture in
            Task { @MainActor in self?.lastGesture = gesture }
        }
    }

    // MARK: - Engine lifecycle

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
        isWatchingMouseButtons = engine.isWatchingMouseButtons
    }

    func stopEngine() {
        guard isEngineRunning else { return }
        engine.stop()
        isEngineRunning = false
        isWatchingMouseButtons = false
    }

    func toggleEnabled() {
        config.isEnabled.toggle()
    }

    /// Turns physical button watching on or off, starting or stopping the tap
    /// immediately rather than at next launch.
    func setMouseClicksEnabled(_ isEnabled: Bool) {
        config.mouseClicksEnabled = isEnabled
        engine.syncMouseButtonWatching()
        isWatchingMouseButtons = engine.isWatchingMouseButtons
    }

    // MARK: - Selection

    var selectedBindingIndex: Int? {
        guard let selectedBindingID else { return nil }
        return config.bindings.firstIndex { $0.id == selectedBindingID }
    }

    var selectedBinding: GestureBinding? {
        selectedBindingIndex.map { config.bindings[$0] }
    }

    /// The bindings shown around the device on the overview screen.
    ///
    /// Swipes live on the Custom gestures screen, where direction can be shown
    /// spatially, so they're excluded here to keep the overview readable.
    var overviewBindings: [GestureBinding] {
        config.bindings.filter { !$0.gesture.kind.isSwipe }
    }

    func binding(for spec: GestureSpec) -> GestureBinding? {
        config.bindings.first { $0.gesture == spec }
    }

    /// Selects the binding for a gesture, creating an unassigned one if the
    /// slot is empty — so clicking an "Unassigned" direction just works.
    func selectOrCreate(spec: GestureSpec) {
        if let existing = binding(for: spec) {
            selectedBindingID = existing.id
            return
        }
        let binding = GestureBinding(
            gesture: spec,
            action: ActionConfig(type: .middleClick)
        )
        config.bindings.append(binding)
        selectedBindingID = binding.id
    }

    // MARK: - Bindings

    func addBinding() {
        // Default to a gesture that isn't already bound, so the new chip is
        // immediately usable instead of shadowing an existing binding.
        let spec = firstUnboundSpec()
        let binding = GestureBinding(
            gesture: spec,
            action: ActionConfig(type: .middleClick)
        )
        config.bindings.append(binding)
        selectedBindingID = binding.id
        if spec.kind.isSwipe {
            gestureScreenFingerCount = spec.fingerCount
            screen = .customGestures
        } else {
            screen = .device
        }
    }

    private func firstUnboundSpec() -> GestureSpec {
        for kind in [GestureKind.tap, .doubleTap, .hold, .click] {
            for fingers in 2...5 {
                let spec = GestureSpec(fingerCount: fingers, kind: kind)
                if binding(for: spec) == nil { return spec }
            }
        }
        return GestureSpec(fingerCount: 3, kind: .tap)
    }

    func deleteSelectedBinding() {
        guard let index = selectedBindingIndex else { return }
        config.bindings.remove(at: index)
        selectedBindingID = config.bindings.first?.id
    }

    func resetToDefaults() {
        config = ConfigStore.defaultConfig
        selectedBindingID = config.bindings.first?.id
    }

    // MARK: - Actions panel

    var filteredActionSections: [ActionSection] {
        ActionCatalog.sections(matching: actionSearch)
    }

    func isSectionExpanded(_ id: String, default defaultValue: Bool) -> Bool {
        expandedSections[id] ?? defaultValue
    }

    func toggleSection(_ id: String, default defaultValue: Bool) {
        expandedSections[id] = !isSectionExpanded(id, default: defaultValue)
    }

    /// Applies a catalog template to the selected binding.
    ///
    /// Templates needing input only set the action *type*, preserving any
    /// parameters already entered — so re-selecting "Keyboard Shortcut" doesn't
    /// wipe the shortcut the user just recorded.
    func select(template: ActionTemplate) {
        guard let index = selectedBindingIndex else { return }

        switch template.kind {
        case .ready(let action):
            config.bindings[index].action = action
        case .needsInput(let type):
            guard config.bindings[index].action.type != type else { return }
            var action = config.bindings[index].action
            action.type = type
            action.preset = nil
            config.bindings[index].action = action
        }
    }

    // MARK: - Config file

    var configPath: String {
        store.fileURL.path
    }

    /// Version, build number, and commit, for bug reports.
    ///
    /// `Scripts/build_app.sh` stamps all three into the bundle. Running the bare
    /// executable via `swift run` has no bundle plist, hence the fallback.
    var versionSummary: String {
        let info = Bundle.main.infoDictionary
        guard
            let version = info?["CFBundleShortVersionString"] as? String,
            version != "0.0.0"
        else {
            return "unpackaged build (run Scripts/build_app.sh for a versioned one)"
        }

        let build = info?["CFBundleVersion"] as? String ?? "?"
        let sha = info?["MagicBindGitSHA"] as? String ?? "unknown"
        return "\(version) (build \(build), \(sha))"
    }

    func revealConfigInFinder() {
        // Save first: revealing a file that doesn't exist yet just opens the
        // enclosing folder and looks broken.
        do {
            try store.save()
            NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
        } catch {
            lastErrorMessage = error.localizedDescription
        }
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
