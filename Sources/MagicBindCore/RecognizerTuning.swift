import Foundation

/// Tuning constants for `GestureRecognizer`.
///
/// - Important: These defaults are estimates, not measurements. They need
///   real-device calibration, which is why they live in the config and are
///   exposed in the UI — they can be tuned without a rebuild.
public struct RecognizerTuning: Codable, Hashable, Sendable {
    /// Longest contact that can still count as a tap, in seconds.
    public var tapMaxDuration: Double

    /// Largest centroid travel that still counts as a tap, in normalized units.
    public var tapMaxMovement: Double

    /// Centroid travel required before a swipe fires, in normalized units.
    public var swipeMinMovement: Double

    /// Contact duration required before a hold fires, in seconds.
    public var holdMinDuration: Double

    /// Largest centroid travel a hold tolerates, in normalized units.
    public var holdMaxMovement: Double

    /// Longest gap between two taps that still counts as a double tap, in
    /// seconds. Optional so older configs decode; falls back to the default.
    public var doubleTapMaxInterval: Double?

    /// The effective double-tap window.
    public var effectiveDoubleTapMaxInterval: Double {
        doubleTapMaxInterval ?? 0.35
    }

    /// Fewest fingers a touch gesture needs before it counts.
    ///
    /// Defaults to 2, because one finger resting on a mouse is just *holding
    /// the mouse*. Measured on real hardware: simply moving a Magic Mouse
    /// around produced a continuous stream of `1-finger Hold` and
    /// `1-finger Swipe` recognitions. Optional so older configs decode.
    public var minimumFingerCount: Int?

    /// The effective minimum, clamped to something sane.
    public var effectiveMinimumFingerCount: Int {
        min(max(minimumFingerCount ?? 2, 1), 5)
    }

    public init(
        tapMaxDuration: Double = 0.25,
        tapMaxMovement: Double = 0.03,
        swipeMinMovement: Double = 0.08,
        holdMinDuration: Double = 0.5,
        holdMaxMovement: Double = 0.03,
        doubleTapMaxInterval: Double? = 0.35,
        minimumFingerCount: Int? = 2
    ) {
        self.tapMaxDuration = tapMaxDuration
        self.tapMaxMovement = tapMaxMovement
        self.swipeMinMovement = swipeMinMovement
        self.holdMinDuration = holdMinDuration
        self.holdMaxMovement = holdMaxMovement
        self.doubleTapMaxInterval = doubleTapMaxInterval
        self.minimumFingerCount = minimumFingerCount
    }

    public static let `default` = RecognizerTuning()
}
