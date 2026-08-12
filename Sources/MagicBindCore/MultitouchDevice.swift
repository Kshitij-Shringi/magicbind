import Foundation

/// The kind of multitouch device a gesture came from.
///
/// Bindings are scoped by *kind* rather than by device ID: an ID changes when
/// hardware is re-paired, and "run this on my trackpad" is what people actually
/// mean, not "run this on the specific trackpad I owned in March".
public enum DeviceKind: String, Codable, CaseIterable, Sendable {
    case magicMouse
    case magicTrackpad
    case builtInTrackpad
    case other

    public var displayName: String {
        switch self {
        case .magicMouse: return "Magic Mouse"
        case .magicTrackpad: return "Magic Trackpad"
        case .builtInTrackpad: return "Built-in Trackpad"
        case .other: return "Other Device"
        }
    }

    public var symbolName: String {
        switch self {
        case .magicMouse: return "magicmouse"
        case .magicTrackpad, .builtInTrackpad: return "trackpad"
        case .other: return "questionmark.square.dashed"
        }
    }

    /// Whether this is a trackpad, where macOS already claims many multi-finger
    /// gestures for itself.
    public var isTrackpad: Bool {
        self == .magicTrackpad || self == .builtInTrackpad
    }
}

/// Identity and geometry of one attached multitouch device.
public struct MTDeviceInfo: Identifiable, Hashable, Sendable {
    public var deviceID: UInt64
    public var familyID: Int32
    public var isBuiltIn: Bool
    /// Sensor dimensions in the framework's internal units. Only the aspect
    /// ratio is meaningful to us.
    public var surfaceWidth: Int32
    public var surfaceHeight: Int32

    public var id: UInt64 { deviceID }

    public init(
        deviceID: UInt64,
        familyID: Int32,
        isBuiltIn: Bool,
        surfaceWidth: Int32 = 0,
        surfaceHeight: Int32 = 0
    ) {
        self.deviceID = deviceID
        self.familyID = familyID
        self.isBuiltIn = isBuiltIn
        self.surfaceWidth = surfaceWidth
        self.surfaceHeight = surfaceHeight
    }

    public var kind: DeviceKind {
        DeviceClassifier.kind(
            familyID: familyID,
            isBuiltIn: isBuiltIn,
            surfaceWidth: surfaceWidth,
            surfaceHeight: surfaceHeight
        )
    }

    public var displayName: String {
        kind.displayName
    }

    /// The detail line shown in the Devices list, and the thing to quote in a
    /// bug report about an unrecognized device.
    public var technicalSummary: String {
        let surface = surfaceWidth > 0 && surfaceHeight > 0
            ? " · surface \(surfaceWidth)×\(surfaceHeight)"
            : ""
        return "family \(familyID) · \(isBuiltIn ? "built-in" : "external")\(surface)"
    }
}

/// Works out what a device is from the values the private framework reports.
///
/// Family IDs are not documented by Apple. The values below come from what this
/// project has actually observed, plus the sets commonly cited by other projects
/// in this space, and the classifier deliberately degrades to a geometry
/// heuristic rather than to `.other` so an unlisted device still behaves
/// sensibly.
public enum DeviceClassifier {
    /// Observed: 112 on a Magic Mouse. 113 is widely reported for Magic Mouse 2.
    static let magicMouseFamilies: Set<Int32> = [112, 113]

    /// Widely reported for the standalone Magic Trackpad line.
    static let magicTrackpadFamilies: Set<Int32> = [128, 129, 130]

    /// Observed: 106 on a built-in trackpad. Built-in detection doesn't rely on
    /// this set — `isBuiltIn` is authoritative — but it's here for completeness.
    static let builtInTrackpadFamilies: Set<Int32> = [98, 99, 100, 101, 102, 103, 104, 105, 106]

    public static func kind(
        familyID: Int32,
        isBuiltIn: Bool,
        surfaceWidth: Int32 = 0,
        surfaceHeight: Int32 = 0
    ) -> DeviceKind {
        // A built-in device can only be the laptop's own trackpad, whatever
        // family it reports. This is the one signal Apple gives us directly, so
        // it wins over the undocumented family tables.
        if isBuiltIn {
            return .builtInTrackpad
        }
        if magicMouseFamilies.contains(familyID) {
            return .magicMouse
        }
        if magicTrackpadFamilies.contains(familyID) {
            return .magicTrackpad
        }
        if builtInTrackpadFamilies.contains(familyID) {
            return .builtInTrackpad
        }

        // Unknown family. A mouse's touch surface is taller than it is wide
        // (observed 5152×9056); a trackpad is wider than tall (observed
        // 11897×8044). That's a strong enough signal to guess with, and a wrong
        // guess here is recoverable — the user can still toggle the device by
        // hand in the Devices list.
        if surfaceWidth > 0 && surfaceHeight > 0 {
            return surfaceHeight > surfaceWidth ? .magicMouse : .magicTrackpad
        }

        return .other
    }
}
