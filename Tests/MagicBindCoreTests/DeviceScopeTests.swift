import Foundation
import XCTest

@testable import MagicBindCore

/// Tests for device classification and per-device binding scope.
final class DeviceScopeTests: XCTestCase {
    // MARK: - Classification

    func testBuiltInFlagWinsOverFamilyID() {
        // isBuiltIn is the one signal Apple gives us directly, so it must beat
        // the undocumented family tables — including a family we'd otherwise
        // read as a Magic Mouse.
        let kind = DeviceClassifier.kind(familyID: 112, isBuiltIn: true)

        XCTAssertEqual(kind, .builtInTrackpad)
    }

    func testObservedHardwareClassifiesCorrectly() {
        // Both rows measured on a real Mac by probing MTDeviceCreateList.
        let builtIn = DeviceClassifier.kind(
            familyID: 106, isBuiltIn: true, surfaceWidth: 11897, surfaceHeight: 8044
        )
        let magicMouse = DeviceClassifier.kind(
            familyID: 112, isBuiltIn: false, surfaceWidth: 5152, surfaceHeight: 9056
        )

        XCTAssertEqual(builtIn, .builtInTrackpad)
        XCTAssertEqual(magicMouse, .magicMouse)
    }

    func testKnownFamilyIDs() {
        XCTAssertEqual(DeviceClassifier.kind(familyID: 113, isBuiltIn: false), .magicMouse)
        XCTAssertEqual(DeviceClassifier.kind(familyID: 128, isBuiltIn: false), .magicTrackpad)
        XCTAssertEqual(DeviceClassifier.kind(familyID: 130, isBuiltIn: false), .magicTrackpad)
    }

    func testUnknownFamilyFallsBackToSurfaceAspect() {
        // A mouse's touch surface is taller than wide; a trackpad is wider than
        // tall. Guessing beats reporting `.other` and doing nothing.
        let tall = DeviceClassifier.kind(
            familyID: 999, isBuiltIn: false, surfaceWidth: 5000, surfaceHeight: 9000
        )
        let wide = DeviceClassifier.kind(
            familyID: 999, isBuiltIn: false, surfaceWidth: 12000, surfaceHeight: 8000
        )

        XCTAssertEqual(tall, .magicMouse)
        XCTAssertEqual(wide, .magicTrackpad)
    }

    func testUnknownFamilyWithNoDimensionsIsOther() {
        XCTAssertEqual(DeviceClassifier.kind(familyID: 999, isBuiltIn: false), .other)
    }

    func testTrackpadClassification() {
        XCTAssertTrue(DeviceKind.builtInTrackpad.isTrackpad)
        XCTAssertTrue(DeviceKind.magicTrackpad.isTrackpad)
        XCTAssertFalse(DeviceKind.magicMouse.isTrackpad)
        XCTAssertFalse(DeviceKind.other.isTrackpad)
    }

    func testDeviceInfoExposesClassificationAndSummary() {
        let device = MTDeviceInfo(
            deviceID: 288_230_376_166_891_289,
            familyID: 112,
            isBuiltIn: false,
            surfaceWidth: 5152,
            surfaceHeight: 9056
        )

        XCTAssertEqual(device.kind, .magicMouse)
        XCTAssertEqual(device.displayName, "Magic Mouse")
        XCTAssertEqual(device.technicalSummary, "family 112 · external · surface 5152×9056")
        XCTAssertEqual(device.id, device.deviceID)
    }

    // MARK: - Device enable defaults

    func testTrackpadsAreOffByDefaultAndMiceAreOn() {
        // A built-in trackpad already has macOS's own three- and four-finger
        // gestures bound. Claiming them on install would break the machine for
        // anyone who tries this, so trackpads start off.
        let config = AppConfig()

        XCTAssertTrue(config.isDeviceEnabled(.magicMouse))
        XCTAssertFalse(config.isDeviceEnabled(.builtInTrackpad))
        XCTAssertFalse(config.isDeviceEnabled(.magicTrackpad))
        XCTAssertTrue(config.isDeviceEnabled(.other))
    }

    func testEnablingATrackpadPersistsAnExplicitSet() {
        var config = AppConfig()
        XCTAssertNil(config.enabledDeviceKinds)

        config.setDeviceEnabled(.builtInTrackpad, true)

        XCTAssertNotNil(config.enabledDeviceKinds)
        XCTAssertTrue(config.isDeviceEnabled(.builtInTrackpad))
        // Turning one on must not turn the others off.
        XCTAssertTrue(config.isDeviceEnabled(.magicMouse))
    }

    func testDisablingAMouse() {
        var config = AppConfig()
        config.setDeviceEnabled(.magicMouse, false)

        XCTAssertFalse(config.isDeviceEnabled(.magicMouse))
    }

    func testEnabledKindsRoundTripThroughJSON() throws {
        var config = ConfigStore.defaultConfig
        config.setDeviceEnabled(.builtInTrackpad, true)

        let data = try ConfigStore.makeEncoder().encode(config)
        let decoded = try ConfigStore.makeDecoder().decode(AppConfig.self, from: data)

        XCTAssertEqual(decoded, config)
        XCTAssertTrue(decoded.isDeviceEnabled(.builtInTrackpad))
    }

    // MARK: - Per-binding scope

    func testBindingWithNoScopeAppliesEverywhere() {
        let binding = GestureBinding(
            gesture: GestureSpec(fingerCount: 3, kind: .tap),
            action: ActionConfig(type: .middleClick)
        )

        XCTAssertNil(binding.deviceKinds)
        for kind in DeviceKind.allCases {
            XCTAssertTrue(binding.appliesTo(kind), "\(kind.rawValue)")
        }
    }

    func testBindingScopedToOneDevice() {
        let binding = GestureBinding(
            gesture: GestureSpec(fingerCount: 4, kind: .tap),
            action: ActionConfig(type: .middleClick),
            deviceKinds: [.magicMouse]
        )

        XCTAssertTrue(binding.appliesTo(.magicMouse))
        XCTAssertFalse(binding.appliesTo(.builtInTrackpad))
    }

    func testLookupRespectsPerBindingScope() {
        let spec = GestureSpec(fingerCount: 4, kind: .tap)
        var config = AppConfig(
            enabledDeviceKinds: [.magicMouse, .builtInTrackpad],
            bindings: [
                GestureBinding(
                    gesture: spec,
                    action: ActionConfig(type: .middleClick),
                    deviceKinds: [.magicMouse]
                )
            ]
        )

        XCTAssertNotNil(config.binding(for: spec, on: .magicMouse))
        XCTAssertNil(
            config.binding(for: spec, on: .builtInTrackpad),
            "mouse-only binding must not fire from the trackpad"
        )

        // Widening the scope makes it fire from both.
        config.bindings[0].deviceKinds = [.magicMouse, .builtInTrackpad]
        XCTAssertNotNil(config.binding(for: spec, on: .builtInTrackpad))
    }

    func testDisablingADeviceOverridesEveryPerBindingScope() {
        let spec = GestureSpec(fingerCount: 3, kind: .tap)
        let config = AppConfig(
            enabledDeviceKinds: [.magicMouse],
            bindings: [
                GestureBinding(
                    gesture: spec,
                    action: ActionConfig(type: .middleClick),
                    deviceKinds: [.magicMouse, .builtInTrackpad]
                )
            ]
        )

        XCTAssertNotNil(config.binding(for: spec, on: .magicMouse))
        XCTAssertNil(
            config.binding(for: spec, on: .builtInTrackpad),
            "a switched-off device must win over an opted-in binding"
        )
    }

    func testTwoBindingsCanShareAGestureOnDifferentDevices() {
        // The point of per-binding scope: the same physical gesture doing
        // different things depending on which device you make it on.
        let spec = GestureSpec(fingerCount: 3, kind: .tap)
        let config = AppConfig(
            enabledDeviceKinds: [.magicMouse, .builtInTrackpad],
            bindings: [
                GestureBinding(
                    gesture: spec,
                    action: ActionConfig(type: .middleClick),
                    deviceKinds: [.magicMouse]
                ),
                GestureBinding(
                    gesture: spec,
                    action: PresetAction.missionControl.actionConfig,
                    deviceKinds: [.builtInTrackpad]
                )
            ]
        )

        XCTAssertEqual(config.binding(for: spec, on: .magicMouse)?.action.type, .middleClick)
        XCTAssertEqual(
            config.binding(for: spec, on: .builtInTrackpad)?.action.preset,
            .missionControl
        )
    }

    func testDisabledBindingNeverMatches() {
        let spec = GestureSpec(fingerCount: 3, kind: .tap)
        let config = AppConfig(
            bindings: [
                GestureBinding(
                    gesture: spec,
                    action: ActionConfig(type: .middleClick),
                    isEnabled: false
                )
            ]
        )

        XCTAssertNil(config.binding(for: spec, on: .magicMouse))
    }

    // MARK: - Backwards compatibility

    func testPreDeviceScopeConfigDecodesAsUnscoped() throws {
        // A config written before per-device scoping has no `deviceKinds` and no
        // `enabledDeviceKinds`. It must keep working exactly as before: bindings
        // apply everywhere, and the trackpad stays off.
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
                  "id": "3D4E5F60-0000-0000-0000-000000000002",
                  "isEnabled": true,
                  "gesture": { "fingerCount": 3, "kind": "tap" },
                  "action": { "type": "middleClick" }
                }
              ]
            }
            """

        let decoded = try ConfigStore.makeDecoder()
            .decode(AppConfig.self, from: Data(legacy.utf8))

        XCTAssertNil(decoded.enabledDeviceKinds)
        XCTAssertNil(decoded.bindings[0].deviceKinds)
        XCTAssertTrue(decoded.bindings[0].appliesTo(.magicMouse))
        XCTAssertFalse(decoded.isDeviceEnabled(.builtInTrackpad))

        let spec = GestureSpec(fingerCount: 3, kind: .tap)
        XCTAssertNotNil(decoded.binding(for: spec, on: .magicMouse))
        XCTAssertNil(decoded.binding(for: spec, on: .builtInTrackpad))
    }

    func testDefaultConfigBindingsAreUnscoped() {
        for binding in ConfigStore.defaultConfig.bindings {
            XCTAssertNil(
                binding.deviceKinds,
                "defaults should not pin themselves to a device the user may not own"
            )
        }
    }
}
