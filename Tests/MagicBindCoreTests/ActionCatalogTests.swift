import Foundation
import XCTest

@testable import MagicBindCore

final class ActionCatalogTests: XCTestCase {
    // MARK: - Preset integrity

    func testEveryPresetIsRunnable() {
        // ActionExecutor can only run a preset that has either a keyboard
        // shortcut or a media key. A preset with neither would fail silently at
        // runtime, so it must fail here instead.
        for preset in PresetAction.allCases {
            let hasShortcut = preset.shortcut != nil
            let hasMediaKey = preset.mediaKey != nil

            XCTAssertTrue(
                hasShortcut || hasMediaKey,
                "\(preset.rawValue) has neither a shortcut nor a media key"
            )
            XCTAssertFalse(
                hasShortcut && hasMediaKey,
                "\(preset.rawValue) has both a shortcut and a media key; which wins is ambiguous"
            )
        }
    }

    func testOnlyVolumePresetsUseMediaKeys() {
        let mediaPresets = PresetAction.allCases.filter { $0.mediaKey != nil }

        XCTAssertEqual(Set(mediaPresets), Set([.volumeUp, .volumeDown, .mute]))
    }

    func testMediaKeyValuesMatchIOKitConstants() {
        // From ev_keymap.h — wrong values here silently press the wrong media
        // key, which is confusing to debug by hand.
        XCTAssertEqual(PresetAction.volumeUp.mediaKey, 0)
        XCTAssertEqual(PresetAction.volumeDown.mediaKey, 1)
        XCTAssertEqual(PresetAction.mute.mediaKey, 7)
    }

    func testEveryPresetHasADistinctDisplayName() {
        let names = PresetAction.allCases.map(\.displayName)

        XCTAssertEqual(Set(names).count, names.count, "two presets share a display name")
    }

    func testWellKnownPresetShortcuts() {
        XCTAssertEqual(PresetAction.missionControl.shortcutDisplayString, "⌃↑")
        XCTAssertEqual(PresetAction.desktopLeft.shortcutDisplayString, "⌃←")
        XCTAssertEqual(PresetAction.desktopRight.shortcutDisplayString, "⌃→")
        XCTAssertEqual(PresetAction.screenCaptureRegion.shortcutDisplayString, "⇧⌘4")
        XCTAssertEqual(PresetAction.lockScreen.shortcutDisplayString, "⌃⌘Q")
    }

    func testVolumePresetsHaveNoShortcutString() {
        XCTAssertNil(PresetAction.volumeUp.shortcutDisplayString)
        XCTAssertNil(PresetAction.mute.shortcutDisplayString)
    }

    func testPresetActionConfigRoundTrips() throws {
        let action = PresetAction.missionControl.actionConfig
        XCTAssertEqual(action.type, .preset)
        XCTAssertEqual(action.preset, .missionControl)

        let data = try ConfigStore.makeEncoder().encode(action)
        let decoded = try ConfigStore.makeDecoder().decode(ActionConfig.self, from: data)

        XCTAssertEqual(decoded, action)
    }

    // MARK: - Catalog structure

    func testCatalogSectionAndTemplateIDsAreUnique() {
        let sectionIDs = ActionCatalog.sections.map(\.id)
        XCTAssertEqual(Set(sectionIDs).count, sectionIDs.count, "duplicate section id")

        let templateIDs = ActionCatalog.allTemplates.map(\.id)
        XCTAssertEqual(Set(templateIDs).count, templateIDs.count, "duplicate template id")
    }

    func testReadyTemplatesCarryEverythingNeededToRun() {
        for template in ActionCatalog.allTemplates {
            guard case .ready(let action) = template.kind else { continue }

            switch action.type {
            case .preset:
                XCTAssertNotNil(action.preset, "\(template.id) is a preset with no preset set")
            case .middleClick:
                break  // needs no parameters
            case .keyboardShortcut:
                XCTAssertNotNil(action.keyCode, "\(template.id) has no key code")
            case .launchApp, .shellCommand, .appleScript:
                XCTFail("\(template.id) needs user input but is marked ready")
            }
        }
    }

    func testTemplatesNeedingInputCoverTheParameterisedActionTypes() {
        let needsInput: Set<ActionType> = Set(
            ActionCatalog.allTemplates.compactMap { template in
                guard case .needsInput(let type) = template.kind else { return nil }
                return type
            }
        )

        XCTAssertEqual(needsInput, [.keyboardShortcut, .launchApp, .shellCommand, .appleScript])
    }

    // MARK: - Matching

    func testPresetTemplatesMatchOnlyTheirOwnPreset() throws {
        let template = try XCTUnwrap(
            ActionCatalog.allTemplates.first { $0.id == PresetAction.missionControl.rawValue }
        )

        XCTAssertTrue(template.matches(PresetAction.missionControl.actionConfig))
        XCTAssertFalse(template.matches(PresetAction.desktopLeft.actionConfig))
        XCTAssertFalse(template.matches(ActionConfig(type: .middleClick)))
    }

    func testKeyboardShortcutTemplateStaysMatchedWhileTheShortcutIsStillEmpty() {
        // The row has to remain selected while the user is choosing a shortcut,
        // otherwise the inline recorder closes the moment it opens.
        let template = ActionCatalog.allTemplates.first { $0.id == "keyboardShortcut" }

        XCTAssertEqual(template?.matches(ActionConfig(type: .keyboardShortcut)), true)
        XCTAssertEqual(
            template?.matches(ActionConfig(type: .keyboardShortcut, keyCode: 21)),
            true
        )
    }

    func testTemplateLookupFindsThePresetForAnExistingBinding() {
        let found = ActionCatalog.template(matching: PresetAction.paste.actionConfig)

        XCTAssertEqual(found?.id, PresetAction.paste.rawValue)
        XCTAssertEqual(found?.title, "Paste")
    }

    // MARK: - Search

    func testEmptySearchReturnsTheWholeCatalogWithDefaultExpansion() {
        let all = ActionCatalog.sections(matching: "")
        XCTAssertEqual(all.count, ActionCatalog.sections.count)
        XCTAssertEqual(
            all.map(\.isExpandedByDefault),
            ActionCatalog.sections.map(\.isExpandedByDefault)
        )

        XCTAssertEqual(ActionCatalog.sections(matching: "   ").count, ActionCatalog.sections.count)
    }

    func testSearchIsCaseInsensitiveAndDropsEmptySections() {
        let results = ActionCatalog.sections(matching: "MISSION")
        let titles = results.flatMap { $0.templates.map(\.title) }

        XCTAssertEqual(titles, ["Mission Control"])
        XCTAssertEqual(results.count, 1, "sections with no hits should be dropped")
    }

    func testSearchExpandsMatchedSectionsEvenIfCollapsedByDefault() {
        // "Lock Screen" lives in the collapsed System section; finding it and
        // then leaving it collapsed would look like no result at all.
        let results = ActionCatalog.sections(matching: "lock")

        XCTAssertFalse(results.isEmpty)
        for section in results {
            XCTAssertTrue(section.isExpandedByDefault, "\(section.id) came back collapsed")
        }
    }

    func testSearchMatchesSubtitlesSoShortcutsAreFindable() {
        // Subtitles carry the shortcut glyphs, so searching "⌘V" should find
        // Paste even though the title doesn't contain it.
        let results = ActionCatalog.sections(matching: "⌘V")
        let titles = results.flatMap { $0.templates.map(\.title) }

        XCTAssertTrue(titles.contains("Paste"), "got \(titles)")
    }

    func testSearchWithNoMatchesReturnsNothing() {
        XCTAssertTrue(ActionCatalog.sections(matching: "zzzzzz").isEmpty)
    }
}
