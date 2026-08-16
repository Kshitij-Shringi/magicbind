import Foundation
import XCTest

@testable import MagicBindCore

/// Regressions from the first real-hardware test session.
final class ActionSwitchingTests: XCTestCase {
    // MARK: - The fn flag

    func testFunctionFlagIsNotRecordable() {
        // macOS sets `function` on arrow keys and F-keys whether or not the user
        // touched the fn key. Recording ⌃↑ captured control + fn, and posting fn
        // back alongside the arrow key stopped Mission Control from triggering.
        XCTAssertFalse(ShortcutModifiers.displayable.contains(.function))
        XCTAssertFalse(ShortcutModifiers.displayable.contains(.numericPad))
    }

    func testArrowKeyShortcutDropsTheFunctionFlag() {
        // The exact value observed in a real config: option + fn on Up.
        let observed: UInt64 = 8_912_896
        let filtered = ShortcutModifiers(rawValue: observed).intersection(.displayable)

        XCTAssertEqual(filtered, [.option])
        XCTAssertEqual(
            KeyboardShortcutFormatter.displayString(keyCode: 126, modifiers: observed),
            "⌥↑"
        )
    }

    func testMissionControlShortcutSurvivesFiltering() throws {
        // ⌃↑ must round-trip intact — the filter has to remove fn without
        // touching the modifier the user actually held.
        let missionControl = try XCTUnwrap(PresetAction.missionControl.shortcut)
        XCTAssertEqual(missionControl.keyCode, 126)
        XCTAssertEqual(missionControl.modifiers, [.control])

        let raw = ShortcutModifiers([.control]).rawValue
        let filtered = ShortcutModifiers(rawValue: raw | ShortcutModifiers.function.rawValue)
            .intersection(.displayable)

        XCTAssertEqual(filtered, [.control])
        XCTAssertEqual(filtered.rawValue, 262_144)
    }

    func testEveryPresetShortcutIsUnaffectedByTheFilter() {
        for preset in PresetAction.allCases {
            guard let shortcut = preset.shortcut else { continue }
            let filtered = shortcut.modifiers.intersection(.displayable)
            XCTAssertEqual(
                filtered,
                shortcut.modifiers,
                "\(preset.rawValue) loses modifiers when filtered"
            )
        }
    }

    // MARK: - Switching action type

    func testSwitchingTypeDropsParametersThatNoLongerApply() {
        // Observed in a real config: a middleClick action still carrying the
        // keyCode and modifiers from when it was a keyboard shortcut.
        let shortcut = ActionConfig(
            type: .keyboardShortcut,
            keyCode: 8,
            modifiers: ShortcutModifiers.command.rawValue
        )

        let switched = shortcut.switchingType(to: .middleClick)

        XCTAssertEqual(switched.type, .middleClick)
        XCTAssertNil(switched.keyCode)
        XCTAssertNil(switched.modifiers)
    }

    func testSwitchingToTheSameTypeIsANoOp() {
        // Re-selecting "Keyboard Shortcut" in the picker must not wipe the
        // shortcut the user just recorded.
        let shortcut = ActionConfig(type: .keyboardShortcut, keyCode: 21, modifiers: 1)

        XCTAssertEqual(shortcut.switchingType(to: .keyboardShortcut), shortcut)
    }

    func testSwitchingKeepsOnlyTheRelevantParameter() {
        let everything = ActionConfig(
            type: .shellCommand,
            preset: .paste,
            keyCode: 21,
            modifiers: 4,
            bundleIdentifier: "com.apple.Safari",
            command: "ls",
            script: "beep"
        )

        let toApp = everything.switchingType(to: .launchApp)
        XCTAssertEqual(toApp.bundleIdentifier, "com.apple.Safari")
        XCTAssertNil(toApp.command)
        XCTAssertNil(toApp.script)
        XCTAssertNil(toApp.keyCode)
        XCTAssertNil(toApp.preset)

        let toScript = everything.switchingType(to: .appleScript)
        XCTAssertEqual(toScript.script, "beep")
        XCTAssertNil(toScript.command)

        let toPreset = everything.switchingType(to: .preset)
        XCTAssertEqual(toPreset.preset, .paste)
        XCTAssertNil(toPreset.command)

        let toShortcut = everything.switchingType(to: .keyboardShortcut)
        XCTAssertEqual(toShortcut.keyCode, 21)
        XCTAssertEqual(toShortcut.modifiers, 4)
        XCTAssertNil(toShortcut.command)
    }

    func testSwitchingProducesJSONWithNoLeftoverKeys() throws {
        let switched = ActionConfig(type: .keyboardShortcut, keyCode: 8, modifiers: 1)
            .switchingType(to: .middleClick)

        let data = try ConfigStore.makeEncoder().encode(switched)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertFalse(json.contains("keyCode"), "got \(json)")
        XCTAssertFalse(json.contains("modifiers"), "got \(json)")
    }
}
