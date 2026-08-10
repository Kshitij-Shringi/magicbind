import Foundation
import XCTest

@testable import MagicBindCore

/// Tests for `GestureSpec` normalization, gesture-kind metadata, and that
/// configs written before click support still decode.
final class GestureSpecTests: XCTestCase {
    // MARK: - GestureSpec normalization

    func testClickSpecsDefaultToTheLeftButton() {
        let spec = GestureSpec(fingerCount: 1, kind: .click)

        XCTAssertEqual(spec.button, .left)
    }

    func testNonClickSpecsDiscardAnyButton() {
        // Otherwise a tap carrying a stray button would never match the tap the
        // recognizer emits, and the binding would look broken.
        let spec = GestureSpec(fingerCount: 3, kind: .tap, button: .right)

        XCTAssertNil(spec.button)
        XCTAssertEqual(spec, GestureSpec(fingerCount: 3, kind: .tap))
    }

    func testDisplayNames() {
        XCTAssertEqual(GestureSpec(fingerCount: 3, kind: .tap).displayName, "3-finger Tap")
        XCTAssertEqual(
            GestureSpec(fingerCount: 3, kind: .doubleTap).displayName,
            "3-finger Double Tap"
        )
        XCTAssertEqual(
            GestureSpec(fingerCount: 2, kind: .click, button: .right).displayName,
            "2-finger Right Button Click"
        )
        // A bare click has no finger prefix — "0-finger Click" reads wrong.
        XCTAssertEqual(
            GestureSpec(fingerCount: 0, kind: .click, button: .left).displayName,
            "Left Button Click"
        )
    }

    func testOnlyClickRequiresMouseButtons() {
        for kind in GestureKind.allCases {
            XCTAssertEqual(
                kind.requiresMouseButtons,
                kind == .click,
                "\(kind.rawValue)"
            )
        }
    }

    func testSwipeClassification() {
        let swipes = GestureKind.allCases.filter(\.isSwipe)

        XCTAssertEqual(Set(swipes), Set([.swipeUp, .swipeDown, .swipeLeft, .swipeRight]))
    }

    // MARK: - Config compatibility

    func testConfigWithoutClickFieldsStillDecodes() throws {
        // A 0.1.x config has no `button`, no `mouseClicksEnabled` and no
        // `doubleTapMaxInterval`. Those must decode as absent, not fail.
        let legacy = """
            {
              "version": 1,
              "isEnabled": true,
              "tuning": {
                "tapMaxDuration": 0.25,
                "tapMaxMovement": 0.03,
                "swipeMinMovement": 0.08,
                "holdMinDuration": 0.5,
                "holdMaxMovement": 0.03
              },
              "bindings": [
                {
                  "id": "3D4E5F60-0000-0000-0000-000000000001",
                  "isEnabled": true,
                  "gesture": { "fingerCount": 3, "kind": "tap" },
                  "action": { "type": "middleClick" }
                }
              ]
            }
            """

        let decoded = try ConfigStore.makeDecoder()
            .decode(AppConfig.self, from: Data(legacy.utf8))

        XCTAssertEqual(decoded.bindings.count, 1)
        XCTAssertNil(decoded.bindings[0].gesture.button)
        XCTAssertFalse(decoded.isMouseClicksEnabled, "click watching must default to off")
        XCTAssertEqual(decoded.tuning.effectiveDoubleTapMaxInterval, 0.35)
    }

    func testMouseClickWatchingIsOffByDefault() {
        XCTAssertFalse(AppConfig().isMouseClicksEnabled)
        XCTAssertFalse(ConfigStore.defaultConfig.isMouseClicksEnabled)
    }
}
