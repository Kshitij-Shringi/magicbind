import Foundation
import XCTest

@testable import MagicBindCore

final class ConfigStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MagicBindTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let directory, FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        directory = nil
        try super.tearDownWithError()
    }

    private var configURL: URL {
        directory.appendingPathComponent("config.json", isDirectory: false)
    }

    // MARK: - Codable round trip

    func testAppConfigSurvivesAnEncodeDecodeRoundTrip() throws {
        let original = AppConfig(
            isEnabled: false,
            tuning: RecognizerTuning(
                tapMaxDuration: 0.31,
                tapMaxMovement: 0.04,
                swipeMinMovement: 0.11,
                holdMinDuration: 0.62,
                holdMaxMovement: 0.02
            ),
            bindings: [
                GestureBinding(
                    gesture: GestureSpec(fingerCount: 3, kind: .tap),
                    action: ActionConfig(type: .middleClick)
                ),
                GestureBinding(
                    gesture: GestureSpec(fingerCount: 4, kind: .swipeUp),
                    action: ActionConfig(
                        type: .keyboardShortcut,
                        keyCode: 21,
                        modifiers: 0x0010_0000 | 0x0002_0000
                    )
                ),
                GestureBinding(
                    gesture: GestureSpec(fingerCount: 2, kind: .swipeLeft),
                    action: ActionConfig(type: .launchApp, bundleIdentifier: "com.apple.Safari"),
                    isEnabled: false
                ),
                GestureBinding(
                    gesture: GestureSpec(fingerCount: 5, kind: .hold),
                    action: ActionConfig(type: .shellCommand, command: "open -a Terminal")
                ),
                GestureBinding(
                    gesture: GestureSpec(fingerCount: 2, kind: .swipeDown),
                    action: ActionConfig(type: .appleScript, script: "display notification \"hi\"")
                )
            ]
        )

        let data = try ConfigStore.makeEncoder().encode(original)
        let decoded = try ConfigStore.makeDecoder().decode(AppConfig.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func testDefaultConfigSurvivesAnEncodeDecodeRoundTrip() throws {
        let data = try ConfigStore.makeEncoder().encode(ConfigStore.defaultConfig)
        let decoded = try ConfigStore.makeDecoder().decode(AppConfig.self, from: data)

        XCTAssertEqual(decoded, ConfigStore.defaultConfig)
    }

    func testUnsetActionParametersStayAbsentFromTheJSON() throws {
        let config = AppConfig(
            bindings: [
                GestureBinding(
                    gesture: GestureSpec(fingerCount: 3, kind: .tap),
                    action: ActionConfig(type: .middleClick)
                )
            ]
        )

        let data = try ConfigStore.makeEncoder().encode(config)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        // A middle-click binding has no key code or script, and the file
        // people hand-edit shouldn't be cluttered with nulls for them.
        XCTAssertFalse(json.contains("keyCode"))
        XCTAssertFalse(json.contains("script"))
        XCTAssertTrue(json.contains("middleClick"))
    }

    // MARK: - Disk round trip

    func testSaveThenLoadRestoresTheSameConfig() throws {
        let store = ConfigStore(fileURL: configURL)
        var config = ConfigStore.defaultConfig
        config.isEnabled = false
        config.tuning.swipeMinMovement = 0.13
        try store.update(config)

        let reloaded = ConfigStore(fileURL: configURL, config: AppConfig())
        let loaded = try reloaded.load()

        XCTAssertEqual(loaded, config)
        XCTAssertEqual(reloaded.config, config)
    }

    func testSaveCreatesMissingIntermediateDirectories() throws {
        let nested = directory
            .appendingPathComponent("a", isDirectory: true)
            .appendingPathComponent("b", isDirectory: true)
            .appendingPathComponent("config.json", isDirectory: false)

        let store = ConfigStore(fileURL: nested)
        try store.save()

        XCTAssertTrue(FileManager.default.fileExists(atPath: nested.path))
    }

    func testLoadingWithNoFileOnDiskKeepsTheInMemoryConfig() throws {
        let store = ConfigStore(fileURL: configURL)

        let loaded = try store.load()

        XCTAssertEqual(loaded, ConfigStore.defaultConfig)
        XCTAssertFalse(FileManager.default.fileExists(atPath: configURL.path))
    }

    func testLoadingCorruptJSONThrows() throws {
        try Data("not json".utf8).write(to: configURL)
        let store = ConfigStore(fileURL: configURL)

        XCTAssertThrowsError(try store.load())
    }

    // MARK: - Migration

    func testConfigFromANewerBuildIsRejectedRatherThanSilentlyDowngraded() throws {
        var future = ConfigStore.defaultConfig
        future.version = AppConfig.currentVersion + 1
        try Data(ConfigStore.makeEncoder().encode(future)).write(to: configURL)

        let store = ConfigStore(fileURL: configURL)

        XCTAssertThrowsError(try store.load()) { error in
            guard case ConfigStore.StoreError.unsupportedVersion(let version) = error else {
                return XCTFail("expected unsupportedVersion, got \(error)")
            }
            XCTAssertEqual(version, AppConfig.currentVersion + 1)
        }
    }

    func testMigrationStampsTheCurrentVersion() throws {
        var old = ConfigStore.defaultConfig
        old.version = 0

        let migrated = try ConfigStore.migrate(old)

        XCTAssertEqual(migrated.version, AppConfig.currentVersion)
        XCTAssertEqual(migrated.bindings, old.bindings)
    }

    // MARK: - Lookup

    func testBindingLookupMatchesOnGestureAndSkipsDisabledBindings() {
        let config = ConfigStore.defaultConfig

        XCTAssertEqual(
            config.binding(for: GestureSpec(fingerCount: 3, kind: .tap))?.action.type,
            .middleClick
        )
        XCTAssertNil(config.binding(for: GestureSpec(fingerCount: 3, kind: .swipeUp)))
        XCTAssertNil(config.binding(for: GestureSpec(fingerCount: 2, kind: .tap)))

        var disabled = config
        for index in disabled.bindings.indices {
            disabled.bindings[index].isEnabled = false
        }
        XCTAssertNil(disabled.binding(for: GestureSpec(fingerCount: 3, kind: .tap)))
    }

    func testDefaultConfigBindsThreeFingerTapToMiddleClick() {
        let binding = ConfigStore.defaultConfig
            .binding(for: GestureSpec(fingerCount: 3, kind: .tap))

        XCTAssertEqual(binding?.action.type, .middleClick)
    }
}
