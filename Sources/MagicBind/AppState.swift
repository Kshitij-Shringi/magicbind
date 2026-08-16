import AppKit
import Combine
import Foundation
import MagicBindCore
import SwiftUI

/// A sidebar group of bindings sharing a gesture kind.
struct BindingGroup: Identifiable {
    let id: String
    let title: String
    let bindings: [GestureBinding]
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

    @Published var selection: Selection?
    @Published var sidebarSearch: String = ""

    /// The most recent error, surfaced in the status bar.
    @Published var lastErrorMessage: String?

    /// The most recently recognized gesture, and which device produced it.
    @Published var lastGesture: GestureSpec?
    @Published var lastGestureDescription: String?

    /// Devices the reader found at startup.
    @Published private(set) var detectedDevices: [MTDeviceInfo] = []

    @Published private(set) var isEngineRunning = false
    @Published private(set) var isWatchingMouseButtons = false

    /// Whether the app holds Accessibility permission.
    ///
    /// Distinct from Input Monitoring, and the distinction bites: touch frames
    /// and click detection use listen-only taps and need only Input Monitoring,
    /// so gestures can be recognized perfectly while every action silently
    /// fails and reserved shortcuts can't be recorded.
    @Published private(set) var isAccessibilityTrusted = ActionExecutor.isAccessibilityTrusted

    /// Touch frames delivered so far, polled for the status bar. Zero while you
    /// are touching the device means the reader is dead — a completely different
    /// problem from a mis-tuned threshold, and worth being able to see at once.
    @Published private(set) var frameCount = 0

    private var frameCountTimer: Timer?

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
        self.selection = store.config.bindings.first.map { Selection.binding($0.id) }

        engine.errorHandler = { [weak self] error in
            Task { @MainActor in self?.lastErrorMessage = error.localizedDescription }
        }
        engine.gestureHandler = { [weak self] gesture, device in
            Task { @MainActor in
                self?.lastGesture = gesture
                let source = device?.displayName ?? "unknown device"
                self?.lastGestureDescription = "\(gesture.displayName) · \(source)"
            }
        }
        engine.devicesHandler = { [weak self] devices in
            Task { @MainActor in self?.detectedDevices = devices }
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
        detectedDevices = engine.devices
        isWatchingMouseButtons = engine.isWatchingMouseButtons
        startFrameCountPolling()
    }

    /// Polls rather than publishing per frame: frames arrive hundreds of times a
    /// second, and driving SwiftUI at that rate would be absurd.
    private func startFrameCountPolling() {
        frameCountTimer?.invalidate()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let latest = self.engine.frameCount
                if latest != self.frameCount { self.frameCount = latest }

                let trusted = ActionExecutor.isAccessibilityTrusted
                if trusted != self.isAccessibilityTrusted {
                    self.isAccessibilityTrusted = trusted
                    // Clear the stale complaint the moment permission appears.
                    if trusted { self.lastErrorMessage = nil }
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        frameCountTimer = timer
    }

    func stopEngine() {
        guard isEngineRunning else { return }
        frameCountTimer?.invalidate()
        frameCountTimer = nil
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

    // MARK: - Devices

    /// Kinds actually attached right now.
    var detectedKinds: Set<DeviceKind> {
        Set(detectedDevices.map(\.kind))
    }

    /// Kinds worth offering in a "runs on" list: what's attached, plus anything
    /// the user has already scoped a binding to, so an unplugged device's
    /// bindings stay editable.
    var knownDeviceKinds: [DeviceKind] {
        var kinds = detectedKinds
        for binding in config.bindings {
            kinds.formUnion(binding.deviceKinds ?? [])
        }
        if kinds.isEmpty {
            kinds = [.magicMouse]
        }
        return DeviceKind.allCases.filter { kinds.contains($0) }
    }

    var enabledDeviceCount: Int {
        detectedDevices.filter { config.isDeviceEnabled($0.kind) }.count
    }

    func deviceEnabledBinding(_ kind: DeviceKind) -> Binding<Bool> {
        Binding(
            get: { [weak self] in self?.config.isDeviceEnabled(kind) ?? false },
            set: { [weak self] isEnabled in
                self?.config.setDeviceEnabled(kind, isEnabled)
            }
        )
    }

    // MARK: - Sidebar

    /// Bindings grouped by gesture kind, filtered by the search field.
    var bindingGroups: [BindingGroup] {
        let query = sidebarSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = query.isEmpty
            ? config.bindings
            : config.bindings.filter { matches($0, query: query) }

        return GestureKind.allCases.compactMap { kind in
            let group = matching.filter { $0.gesture.kind == kind }
            guard !group.isEmpty else { return nil }
            return BindingGroup(
                id: kind.rawValue,
                title: pluralTitle(for: kind),
                bindings: group.sorted { $0.gesture.fingerCount < $1.gesture.fingerCount }
            )
        }
    }

    private func matches(_ binding: GestureBinding, query: String) -> Bool {
        let haystack = [
            binding.gesture.displayName,
            binding.action.displaySummary
        ].joined(separator: " ")
        return haystack.range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) != nil
    }

    private func pluralTitle(for kind: GestureKind) -> String {
        switch kind {
        case .tap: return "Taps"
        case .doubleTap: return "Double Taps"
        case .click: return "Clicks"
        case .hold: return "Holds"
        case .swipeUp: return "Swipe Up"
        case .swipeDown: return "Swipe Down"
        case .swipeLeft: return "Swipe Left"
        case .swipeRight: return "Swipe Right"
        }
    }

    // MARK: - Selection

    var selectedBindingID: GestureBinding.ID? {
        guard case .binding(let id) = selection else { return nil }
        return id
    }

    var selectedBindingIndex: Int? {
        guard let selectedBindingID else { return nil }
        return config.bindings.firstIndex { $0.id == selectedBindingID }
    }

    var selectedBinding: GestureBinding? {
        selectedBindingIndex.map { config.bindings[$0] }
    }

    // MARK: - Bindings

    func addBinding() {
        let spec = firstUnboundSpec()
        let binding = GestureBinding(
            gesture: spec,
            action: ActionConfig(type: .middleClick)
        )
        config.bindings.append(binding)
        selection = .binding(binding.id)
    }

    /// Picks a gesture that isn't already bound, so a new row is immediately
    /// usable instead of shadowing an existing binding.
    private func firstUnboundSpec() -> GestureSpec {
        for kind in [GestureKind.tap, .doubleTap, .hold, .swipeLeft, .swipeRight, .click] {
            for fingers in 2...5 {
                let spec = GestureSpec(fingerCount: fingers, kind: kind)
                if !config.bindings.contains(where: { $0.gesture == spec }) {
                    return spec
                }
            }
        }
        return GestureSpec(fingerCount: 3, kind: .tap)
    }

    func deleteSelectedBinding() {
        guard let index = selectedBindingIndex else { return }
        config.bindings.remove(at: index)
        selection = config.bindings.first.map { Selection.binding($0.id) }
    }

    func resetToDefaults() {
        config = ConfigStore.defaultConfig
        selection = config.bindings.first.map { Selection.binding($0.id) }
    }

    /// Warns when another enabled binding claims the same gesture on an
    /// overlapping device, since only the first one found will ever run.
    func conflictDescription(forBindingAt index: Int) -> String? {
        guard config.bindings.indices.contains(index) else { return nil }
        let binding = config.bindings[index]
        guard binding.isEnabled else { return nil }

        let others = config.bindings.enumerated().filter { offset, other in
            offset != index
                && other.isEnabled
                && other.gesture == binding.gesture
                && !overlappingKinds(binding, other).isEmpty
        }
        guard let (_, first) = others.first else { return nil }

        let shared = overlappingKinds(binding, first)
            .map(\.displayName)
            .sorted()
            .joined(separator: ", ")
        return """
            Another enabled binding uses this same gesture on \(shared) \
            (\(first.action.displaySummary)). Only the first match runs.
            """
    }

    private func overlappingKinds(
        _ lhs: GestureBinding,
        _ rhs: GestureBinding
    ) -> Set<DeviceKind> {
        let all = Set(knownDeviceKinds)
        let left = lhs.deviceKinds ?? all
        let right = rhs.deviceKinds ?? all
        return left.intersection(right).filter { config.isDeviceEnabled($0) }
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

// MARK: - Permissions and config file

@MainActor
extension AppState {
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

    /// Opens System Settings directly at the Accessibility list.
    func openAccessibilitySettings() {
        let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }

    /// Re-asks the system, and re-triggers the prompt if it hasn't been shown.
    func recheckAccessibility() {
        if !ActionExecutor.isAccessibilityTrusted {
            ActionExecutor.requestAccessibilityPermission()
        }
        isAccessibilityTrusted = ActionExecutor.isAccessibilityTrusted
        if isAccessibilityTrusted { lastErrorMessage = nil }
    }

    /// Relaunches the app, which is what actually makes a fresh grant stick.
    func relaunch() {
        let url = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
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

}
