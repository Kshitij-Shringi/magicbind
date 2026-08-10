import Foundation

/// Loads and saves `AppConfig` as plain JSON.
///
/// The file lives at
/// `~/Library/Application Support/MagicBind/config.json` by default and is
/// written pretty-printed with sorted keys, so it stays hand-editable and
/// diffs cleanly in git. The file URL is injectable so tests can round-trip
/// through a temporary directory instead of the user's real config.
public final class ConfigStore {
    public enum StoreError: Error, LocalizedError {
        case unsupportedVersion(Int)

        public var errorDescription: String? {
            switch self {
            case .unsupportedVersion(let version):
                return """
                    Config file is version \(version), but this build of \
                    MagicBind understands at most version \
                    \(AppConfig.currentVersion). Update MagicBind, or move the \
                    file aside to start from defaults.
                    """
            }
        }
    }

    /// The config file this store reads and writes.
    public let fileURL: URL

    /// The in-memory config. Starts at `defaultConfig` until `load()` runs.
    public private(set) var config: AppConfig

    public init(fileURL: URL? = nil, config: AppConfig = ConfigStore.defaultConfig) {
        self.fileURL = fileURL ?? Self.defaultFileURL
        self.config = config
    }

    /// `~/Library/Application Support/MagicBind/config.json`
    public static var defaultFileURL: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory())

        return base
            .appendingPathComponent("MagicBind", isDirectory: true)
            .appendingPathComponent("config.json", isDirectory: false)
    }

    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        JSONDecoder()
    }

    /// Reads the config from disk, replacing the in-memory copy.
    ///
    /// A missing file is not an error — it means a first launch, and leaves
    /// the current in-memory config in place.
    @discardableResult
    public func load() throws -> AppConfig {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return config
        }

        let data = try Data(contentsOf: fileURL)
        let loaded = try Self.makeDecoder().decode(AppConfig.self, from: data)
        config = try Self.migrate(loaded)
        return config
    }

    /// Writes the in-memory config to disk, creating the containing directory
    /// if needed.
    public func save() throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let data = try Self.makeEncoder().encode(config)
        try data.write(to: fileURL, options: .atomic)
    }

    /// Replaces the in-memory config and persists it.
    public func update(_ newConfig: AppConfig) throws {
        config = newConfig
        try save()
    }

    /// Brings an older config forward to the current schema version.
    ///
    /// There is only one version so far, so this exists to reject files from
    /// a *newer* build rather than silently dropping fields the user set.
    static func migrate(_ config: AppConfig) throws -> AppConfig {
        guard config.version <= AppConfig.currentVersion else {
            throw StoreError.unsupportedVersion(config.version)
        }
        var migrated = config
        migrated.version = AppConfig.currentVersion
        return migrated
    }

    /// The bindings a fresh install starts with.
    ///
    /// Deliberately tiny: two gestures that are unambiguous on a Magic Mouse
    /// and that people actually asked MiddleClick for.
    public static let defaultConfig = AppConfig(
        bindings: [
            GestureBinding(
                gesture: GestureSpec(fingerCount: 3, kind: .tap),
                action: ActionConfig(type: .middleClick)
            ),
            GestureBinding(
                gesture: GestureSpec(fingerCount: 4, kind: .tap),
                // Cmd+Shift+4 — the screenshot region tool. keyCode 21 is "4"
                // on a US ANSI layout; modifiers are CGEventFlags raw values
                // (maskCommand 0x100000 | maskShift 0x20000).
                action: ActionConfig(
                    type: .keyboardShortcut,
                    keyCode: 21,
                    modifiers: 0x0010_0000 | 0x0002_0000
                )
            )
        ]
    )
}
