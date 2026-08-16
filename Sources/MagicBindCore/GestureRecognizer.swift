import Foundation

/// Turns a stream of raw multitouch frames into discrete gestures.
///
/// The recognizer is deliberately free of any dependency on wall-clock time or
/// on the private framework: it is driven entirely by
/// `process(fingers:timestamp:)`, with the caller supplying the frame
/// timestamp. That makes the whole classification path unit-testable with
/// synthetic `MTFinger` arrays, which is exactly what
/// `GestureRecognizerTests` does.
///
/// A "session" is one continuous period of contact — from the first finger
/// touching down to the last finger lifting. At most one gesture is emitted
/// per session.
public final class GestureRecognizer {
    /// Threshold constants. Mutable so the preferences UI can retune the
    /// recognizer live without rebuilding it.
    public var tuning: RecognizerTuning

    private struct Session {
        var startTimestamp: Double
        var baselineCentroid: MTPoint
        var lastContactTimestamp: Double
        var lastCentroid: MTPoint
        var contactCount: Int
        var peakContactCount: Int
        var hasEmitted: Bool
    }

    private var session: Session?

    /// When and with how many fingers the last tap landed, so the next tap can
    /// be promoted to a double tap.
    private var lastTap: (timestamp: Double, fingerCount: Int)?

    public init(tuning: RecognizerTuning = .default) {
        self.tuning = tuning
    }

    /// Discards any in-progress session. Call this when the engine is
    /// disabled or the device disconnects, so a stale session can't emit a
    /// gesture on the next frame.
    public func reset() {
        session = nil
        lastTap = nil
    }

    /// Classifies a physical button press as a click gesture, using however
    /// many fingers are currently on the surface.
    ///
    /// Called by `GestureEngine` from `MouseButtonMonitor`, separately from the
    /// touch frame stream, because button events and touch frames arrive on
    /// different callbacks. Only presses produce gestures; releases are ignored.
    ///
    /// - Returns: the click gesture, or `nil` for a button release.
    public func processButton(
        _ button: MouseButton,
        isDown: Bool,
        timestamp: Double
    ) -> GestureSpec? {
        guard isDown else { return nil }

        // A click with fingers resting on the surface is a different gesture
        // from a bare click, so the current contact count is part of the spec.
        let fingers = session?.contactCount ?? 0

        // A click ends any tap/hold in progress — the user clicked rather than
        // tapped — and clears the double-tap history so a click between two taps
        // doesn't join them.
        session?.hasEmitted = true
        lastTap = nil

        return GestureSpec(fingerCount: fingers, kind: .click, button: button)
    }

    /// Feeds one multitouch frame in and returns a gesture if this frame
    /// completed one.
    ///
    /// - Parameters:
    ///   - fingers: every finger in the frame. Fingers not in contact
    ///     (hovering, lifting) are ignored.
    ///   - timestamp: the frame's timestamp, in seconds. Only differences
    ///     matter, so any monotonic clock works.
    /// - Returns: the recognized gesture, or `nil` if this frame did not
    ///   complete one.
    public func process(fingers: [MTFinger], timestamp: Double) -> GestureSpec? {
        let contacts = fingers.filter(\.isContact)

        guard !contacts.isEmpty else {
            return endSession()
        }

        let centroid = Self.centroid(of: contacts)

        guard var current = session else {
            session = Session(
                startTimestamp: timestamp,
                baselineCentroid: centroid,
                lastContactTimestamp: timestamp,
                lastCentroid: centroid,
                contactCount: contacts.count,
                peakContactCount: contacts.count,
                hasEmitted: false
            )
            return nil
        }

        // Fingers rarely land simultaneously: a three-finger gesture usually
        // arrives as a 1-, then 2-, then 3-contact frame. Each of those steps
        // moves the centroid for reasons that have nothing to do with the
        // user moving their hand, so re-baseline on any count change. The
        // session's start time is preserved, so tap/hold timing still measures
        // from first contact.
        if contacts.count != current.contactCount {
            current.contactCount = contacts.count
            current.peakContactCount = max(current.peakContactCount, contacts.count)
            current.baselineCentroid = centroid
        }

        current.lastCentroid = centroid
        current.lastContactTimestamp = timestamp
        session = current

        guard !current.hasEmitted else { return nil }

        let dx = Double(centroid.x - current.baselineCentroid.x)
        let dy = Double(centroid.y - current.baselineCentroid.y)
        let travel = (dx * dx + dy * dy).squareRoot()
        let elapsed = timestamp - current.startTimestamp

        if travel >= tuning.swipeMinMovement {
            // The session is still marked emitted even when the gesture is
            // dropped for having too few fingers — otherwise a one-finger drag
            // would re-test on every subsequent frame.
            current.hasEmitted = true
            session = current
            guard meetsMinimum(current.peakContactCount) else { return nil }
            return GestureSpec(
                fingerCount: current.peakContactCount,
                kind: Self.swipeKind(dx: dx, dy: dy)
            )
        }

        if elapsed >= tuning.holdMinDuration && travel <= tuning.holdMaxMovement {
            current.hasEmitted = true
            session = current
            guard meetsMinimum(current.peakContactCount) else { return nil }
            return GestureSpec(fingerCount: current.peakContactCount, kind: .hold)
        }

        return nil
    }

    /// Handles the frame where the last finger lifted, classifying a tap if
    /// the session was short and stationary enough.
    private func endSession() -> GestureSpec? {
        guard let finished = session else { return nil }
        session = nil

        guard !finished.hasEmitted else { return nil }

        let dx = Double(finished.lastCentroid.x - finished.baselineCentroid.x)
        let dy = Double(finished.lastCentroid.y - finished.baselineCentroid.y)
        let travel = (dx * dx + dy * dy).squareRoot()

        // Measured to the last frame that still had contact, not to the frame
        // that reported the lift — the gap between those two is reader
        // latency, not part of the user's gesture.
        let duration = finished.lastContactTimestamp - finished.startTimestamp

        guard duration <= tuning.tapMaxDuration, travel <= tuning.tapMaxMovement else {
            // An abandoned gesture shouldn't leave a half-finished double tap
            // armed for whatever the user does next.
            lastTap = nil
            return nil
        }

        let fingerCount = finished.peakContactCount
        guard meetsMinimum(fingerCount) else {
            lastTap = nil
            return nil
        }
        let liftTimestamp = finished.lastContactTimestamp

        // A second tap of the same finger count, soon enough after the first,
        // is a double tap.
        //
        // Note this emits `.tap` for the first tap and `.doubleTap` for the
        // second — it does not retroactively suppress the first. Suppressing it
        // would mean delaying every tap by the double-tap window, which makes
        // single taps feel laggy. Bind one or the other, not both, unless you
        // want both to fire.
        if let previous = lastTap,
           previous.fingerCount == fingerCount,
           liftTimestamp - previous.timestamp <= tuning.effectiveDoubleTapMaxInterval {
            lastTap = nil
            return GestureSpec(fingerCount: fingerCount, kind: .doubleTap)
        }

        lastTap = (timestamp: liftTimestamp, fingerCount: fingerCount)
        return GestureSpec(fingerCount: fingerCount, kind: .tap)
    }

    /// Whether a touch gesture had enough fingers to count.
    ///
    /// One finger resting on a mouse is just holding the mouse — on real
    /// hardware that produced a constant stream of one-finger holds and swipes
    /// during ordinary use. Clicks are deliberately *not* gated here: a click is
    /// an explicit act, never an accident of gripping the device.
    private func meetsMinimum(_ fingerCount: Int) -> Bool {
        fingerCount >= tuning.effectiveMinimumFingerCount
    }

    /// The centroid of every finger in contact.
    static func centroid(of contacts: [MTFinger]) -> MTPoint {
        guard !contacts.isEmpty else { return MTPoint() }
        var sumX: Float = 0
        var sumY: Float = 0
        for finger in contacts {
            sumX += finger.normalized.position.x
            sumY += finger.normalized.position.y
        }
        let count = Float(contacts.count)
        return MTPoint(x: sumX / count, y: sumY / count)
    }

    /// Picks a swipe direction from a displacement, using whichever axis
    /// dominates. Normalized `y` increases toward the far edge of the device,
    /// so positive `dy` is upward.
    static func swipeKind(dx: Double, dy: Double) -> GestureKind {
        if abs(dx) > abs(dy) {
            return dx > 0 ? .swipeRight : .swipeLeft
        }
        return dy > 0 ? .swipeUp : .swipeDown
    }
}
