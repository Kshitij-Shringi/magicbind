import Foundation

/// A 2D point as laid out by `MultitouchSupport.framework`.
///
/// - Warning: The layout of every type in this file mirrors the
///   *reverse-engineered* shape of Apple's private multitouch API. It is not
///   published, not guaranteed stable across macOS releases, and not verified
///   on every device. Validate against real frames (see Phase 2 of
///   `ProjectPlan.md`) before trusting it.
public struct MTPoint: Equatable, Sendable {
    public var x: Float
    public var y: Float

    public init(x: Float = 0, y: Float = 0) {
        self.x = x
        self.y = y
    }
}

/// A position/velocity pair. The private framework reports both a normalized
/// readout (0...1 across the device surface) and a millimeter readout.
public struct MTReadout: Equatable, Sendable {
    public var position: MTPoint
    public var velocity: MTPoint

    public init(position: MTPoint = MTPoint(), velocity: MTPoint = MTPoint()) {
        self.position = position
        self.velocity = velocity
    }
}

/// The lifecycle state of a single touch.
///
/// Raw values follow the commonly documented reverse-engineered enumeration.
/// These are the values most likely to need correction after real-device
/// validation — see `ProjectPlan.md` Phase 2.
public enum MTFingerState: Int32, Equatable, Sendable {
    case notTracking = 0
    case startInRange = 1
    case hoverInRange = 2
    case makeTouch = 3
    case touching = 4
    case breakTouch = 5
    case lingerInRange = 6
    case outOfRange = 7

    /// Whether this state represents a finger actually in contact with the
    /// surface, as opposed to hovering, lifting, or not tracked at all.
    public var isContact: Bool {
        self == .makeTouch || self == .touching
    }
}

/// One finger within a single multitouch frame.
///
/// The stored property order and types mirror the C struct the private
/// framework hands back, so an `MTFinger` pointer from the callback can be
/// read directly. Do not reorder these fields.
public struct MTFinger: Equatable, Sendable {
    public var frame: Int32
    public var timestamp: Double
    public var identifier: Int32
    public var state: Int32
    public var fingerID: Int32
    public var handID: Int32
    public var normalized: MTReadout
    public var size: Float
    public var pressure: Int32
    public var angle: Float
    public var majorAxis: Float
    public var minorAxis: Float
    public var absolute: MTReadout
    public var reserved: (Int32, Int32)
    public var zDensity: Float

    /// The `state` field decoded into a Swift enum, or `nil` if the device
    /// reported a value outside the known enumeration.
    public var fingerState: MTFingerState? {
        MTFingerState(rawValue: state)
    }

    /// Whether this finger is in contact with the surface.
    public var isContact: Bool {
        fingerState?.isContact ?? false
    }

    public init(
        frame: Int32 = 0,
        timestamp: Double = 0,
        identifier: Int32 = 0,
        state: Int32 = MTFingerState.touching.rawValue,
        fingerID: Int32 = 0,
        handID: Int32 = 0,
        normalized: MTReadout = MTReadout(),
        size: Float = 0,
        pressure: Int32 = 0,
        angle: Float = 0,
        majorAxis: Float = 0,
        minorAxis: Float = 0,
        absolute: MTReadout = MTReadout(),
        reserved: (Int32, Int32) = (0, 0),
        zDensity: Float = 0
    ) {
        self.frame = frame
        self.timestamp = timestamp
        self.identifier = identifier
        self.state = state
        self.fingerID = fingerID
        self.handID = handID
        self.normalized = normalized
        self.size = size
        self.pressure = pressure
        self.angle = angle
        self.majorAxis = majorAxis
        self.minorAxis = minorAxis
        self.absolute = absolute
        self.reserved = reserved
        self.zDensity = zDensity
    }

    public static func == (lhs: MTFinger, rhs: MTFinger) -> Bool {
        lhs.frame == rhs.frame
            && lhs.timestamp == rhs.timestamp
            && lhs.identifier == rhs.identifier
            && lhs.state == rhs.state
            && lhs.fingerID == rhs.fingerID
            && lhs.handID == rhs.handID
            && lhs.normalized == rhs.normalized
            && lhs.size == rhs.size
            && lhs.pressure == rhs.pressure
            && lhs.angle == rhs.angle
            && lhs.majorAxis == rhs.majorAxis
            && lhs.minorAxis == rhs.minorAxis
            && lhs.absolute == rhs.absolute
            && lhs.reserved == rhs.reserved
            && lhs.zDensity == rhs.zDensity
    }
}

public extension MTFinger {
    /// Convenience constructor for tests and diagnostics: a finger in contact
    /// at a normalized position.
    ///
    /// Normalized coordinates run 0...1 across the device surface, with `y`
    /// increasing toward the far edge — so a positive change in `y` is an
    /// "up" swipe.
    static func contact(
        identifier: Int32,
        x: Float,
        y: Float,
        timestamp: Double = 0,
        state: MTFingerState = .touching
    ) -> MTFinger {
        MTFinger(
            timestamp: timestamp,
            identifier: identifier,
            state: state.rawValue,
            normalized: MTReadout(position: MTPoint(x: x, y: y))
        )
    }
}
