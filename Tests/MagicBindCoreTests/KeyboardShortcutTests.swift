import Foundation
import XCTest

@testable import MagicBindCore

/// Tests for shortcut display formatting.
///
/// Character keys resolve against the machine's *current* keyboard layout, so
/// these tests deliberately avoid asserting that key code 21 renders as "4" —
/// that's only true on US ANSI, and CI shouldn't fail on a Dvorak contributor's
/// laptop. Layout-independent behavior (modifier glyphs, special keys, ordering)
/// is asserted exactly; the layout-dependent path is asserted structurally.
final class KeyboardShortcutTests: XCTestCase {
    // MARK: - Modifier glyphs

    func testModifierGlyphsUseAppleOrdering() {
        // Apple renders modifiers in a fixed order regardless of press order:
        // fn, ⇪, ⌃, ⌥, ⇧, ⌘.
        let all: ShortcutModifiers = [.command, .shift, .option, .control, .capsLock, .function]

        XCTAssertEqual(all.glyphs, "fn⇪⌃⌥⇧⌘")
    }

    func testIndividualModifierGlyphs() {
        XCTAssertEqual(ShortcutModifiers.command.glyphs, "⌘")
        XCTAssertEqual(ShortcutModifiers.shift.glyphs, "⇧")
        XCTAssertEqual(ShortcutModifiers.option.glyphs, "⌥")
        XCTAssertEqual(ShortcutModifiers.control.glyphs, "⌃")
        XCTAssertEqual(ShortcutModifiers.capsLock.glyphs, "⇪")
        XCTAssertEqual(ShortcutModifiers.function.glyphs, "fn")
        XCTAssertEqual(ShortcutModifiers().glyphs, "")
    }

    func testModifierRawValuesMatchCGEventFlags() {
        // ActionExecutor posts these straight through as CGEventFlags, so the
        // raw values must not drift.
        XCTAssertEqual(ShortcutModifiers.capsLock.rawValue, 0x0001_0000)
        XCTAssertEqual(ShortcutModifiers.shift.rawValue, 0x0002_0000)
        XCTAssertEqual(ShortcutModifiers.control.rawValue, 0x0004_0000)
        XCTAssertEqual(ShortcutModifiers.option.rawValue, 0x0008_0000)
        XCTAssertEqual(ShortcutModifiers.command.rawValue, 0x0010_0000)
        XCTAssertEqual(ShortcutModifiers.function.rawValue, 0x0080_0000)
    }

    func testNumericPadIsExcludedFromDisplay() {
        // macOS sets the numeric-pad flag on arrow keys as a side effect. It
        // isn't something the user held down, so it must not show up as a
        // modifier or it would render nonsense on every arrow-key shortcut.
        let flags: ShortcutModifiers = [.command, .numericPad]
        let displayable = flags.intersection(.displayable)

        XCTAssertEqual(displayable.glyphs, "⌘")
        XCTAssertFalse(ShortcutModifiers.displayable.contains(.numericPad))
    }

    // MARK: - Special keys

    func testSpecialKeysRenderAsGlyphs() {
        let cases: [(keyCode: UInt16, expected: String)] = [
            (36, "↩"),   // return
            (48, "⇥"),   // tab
            (49, "␣"),   // space
            (51, "⌫"),   // delete
            (53, "⎋"),   // escape
            (117, "⌦"),  // forward delete
            (123, "←"),
            (124, "→"),
            (125, "↓"),
            (126, "↑"),
            (122, "F1"),
            (111, "F12")
        ]

        for testCase in cases {
            XCTAssertEqual(
                KeyboardShortcutFormatter.keyLabel(for: testCase.keyCode),
                testCase.expected,
                "key code \(testCase.keyCode)"
            )
        }
    }

    func testSpecialKeysAreNotOverriddenByTheKeyboardLayout() {
        // Space has a layout character (" ") but must render as the glyph, not
        // as an invisible blank.
        XCTAssertEqual(KeyboardShortcutFormatter.keyLabel(for: 49), "␣")
    }

    // MARK: - Full shortcut strings

    func testDisplayStringCombinesModifiersAndKey() {
        let combined = KeyboardShortcutFormatter.displayString(
            keyCode: 53,
            modifiers: ShortcutModifiers([.command, .shift]).rawValue
        )

        XCTAssertEqual(combined, "⇧⌘⎋")
    }

    func testDisplayStringWithNoModifiers() {
        XCTAssertEqual(KeyboardShortcutFormatter.displayString(keyCode: 122, modifiers: nil), "F1")
        XCTAssertEqual(KeyboardShortcutFormatter.displayString(keyCode: 122, modifiers: 0), "F1")
    }

    func testDisplayStringIsNilWhenNoKeyRecorded() {
        XCTAssertNil(KeyboardShortcutFormatter.displayString(keyCode: nil, modifiers: nil))
        XCTAssertNil(
            KeyboardShortcutFormatter.displayString(
                keyCode: nil,
                modifiers: ShortcutModifiers.command.rawValue
            )
        )
    }

    func testCharacterKeysResolveToANonEmptySingleCharacterLabel() {
        // Layout-dependent, so assert the shape rather than the character: the
        // default screenshot binding (⌘⇧4 on US ANSI) must at minimum produce
        // the right modifier prefix and a printable key label.
        let shortcut = KeyboardShortcutFormatter.displayString(
            keyCode: 21,
            modifiers: ShortcutModifiers([.command, .shift]).rawValue
        )
        let unwrapped = try? XCTUnwrap(shortcut)

        XCTAssertNotNil(unwrapped)
        XCTAssertTrue(unwrapped?.hasPrefix("⇧⌘") ?? false, "got \(unwrapped ?? "nil")")

        let keyLabel = KeyboardShortcutFormatter.keyLabel(for: 21)
        XCTAssertFalse(keyLabel.isEmpty)
        XCTAssertFalse(keyLabel.contains("Key "), "expected a real label, got \(keyLabel)")
    }

    func testUnmappedKeyCodeFallsBackToTheRawCode() {
        // 0xFF is not a real virtual key code; the label must still be
        // something a bug report can quote.
        XCTAssertEqual(KeyboardShortcutFormatter.keyLabel(for: 0xFF), "Key 255")
    }

    // MARK: - ActionConfig integration

    func testActionConfigExposesItsShortcut() {
        let action = ActionConfig(
            type: .keyboardShortcut,
            keyCode: 53,
            modifiers: ShortcutModifiers.command.rawValue
        )

        XCTAssertEqual(action.shortcutDisplayString, "⌘⎋")
        XCTAssertEqual(action.displaySummary, "Keyboard Shortcut · ⌘⎋")
    }

    func testDefaultScreenshotBindingReportsCommandShift() {
        // ConfigStore's default 4-finger tap is ⌘⇧4. Verify the stored raw
        // modifiers really do decode to Command and Shift.
        let binding = ConfigStore.defaultConfig
            .binding(for: GestureSpec(fingerCount: 4, kind: .tap))
        let modifiers = ShortcutModifiers(rawValue: binding?.action.modifiers ?? 0)

        XCTAssertTrue(modifiers.contains(.command))
        XCTAssertTrue(modifiers.contains(.shift))
        XCTAssertFalse(modifiers.contains(.option))
        XCTAssertFalse(modifiers.contains(.control))
        XCTAssertEqual(modifiers.intersection(.displayable).glyphs, "⇧⌘")
    }

    func testUnsetShortcutSummarySaysNotSet() {
        let action = ActionConfig(type: .keyboardShortcut)

        XCTAssertNil(action.shortcutDisplayString)
        XCTAssertEqual(action.displaySummary, "Keyboard Shortcut · not set")
    }

    func testSummaryForOtherActionTypes() {
        XCTAssertEqual(ActionConfig(type: .middleClick).displaySummary, "Middle Click")
        XCTAssertEqual(
            ActionConfig(type: .launchApp, bundleIdentifier: "com.apple.Safari").displaySummary,
            "Launch App · com.apple.Safari"
        )
        XCTAssertEqual(
            ActionConfig(type: .shellCommand, command: "ls").displaySummary,
            "Shell Command · ls"
        )
    }
}
