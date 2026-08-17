import Foundation

/// Turns a stream of raw multitouch frames into discrete gestures.
///
/// The recognizer is deliberately free of any dependency on wall-clock time or
/// on the private framework: it is driven entirely by
/// `process(fingers:timestamp:)`, with the caller supplying the frame
/// timestamp. That makes the whole classification path unit-testable with
/// synthetic `MTFinger` arrays.
///
/// ## Episodes, not sessions
///
/// The unit of recognition is an **episode**: a stretch of frames with a
/// constant number of fingers in contact. An episode begins whenever the contact
/// count changes and ends when it changes again.
///
/// This matters because of how a mouse is actually held. An earlier version
/// treated one continuous period of contact as the unit, and only evaluated a
/// tap once *every* finger left the surface. On a Magic Mouse a finger never
/// leaves the surface — you are holding the thing — so that period was minutes
/// long, its duration always exceeded `tapMaxDuration`, and taps simply never
/// fired. It appeared to work only when the hand was lifted clear between
/// attempts, which is what testing looks like and not what use looks like.
///
/// Episodes fix that: resting one finger and tapping a second is a 1-contact
/// episode, then a 2-contact episode lasting 50ms, then a 1-contact episode
/// again. The middle one is the tap.
///
/// An episode that ends because the count went **up** is discarded rather than
/// classified — fingers rarely land together, so a three-finger tap arrives as
/// 1, then 2, then 3 contacts, and those first two steps are a hand settling
/// rather than gestures. Only a count going **down** completes a gesture.
public final class GestureRecognizer {
    /// Threshold constants. Mutable so the preferences UI can retune the
    /// recognizer live without rebuilding it.
    public var tuning: RecognizerTuning

    /// A stretch of frames with a constant contact count.
    private struct Episode {
        /// When this contact count was first seen.
        var startTimestamp: Double
        /// The most recent frame still showing this count.
        var lastTimestamp: Double
        var baselineCentroid: MTPoint
        var lastCentroid: MTPoint
        var contactCount: Int
        /// Whether this episode began by fingers being *added*.
        ///
        /// Releasing three fingers one at a time passes through 2 and 1 contacts
        /// on the way down, and those are the tail of one gesture rather than
        /// gestures of their own. Without this, lifting a three-finger tap also
        /// emitted a two-finger tap.
        var enteredByIncrease: Bool
        /// Set once this episode has produced a gesture, so a swipe or hold
        /// can't fire twice and can't be followed by a tap.
        var hasEmitted: Bool
    }

    private var episode: Episode?

    /// When and with how many fingers the last tap landed, so the next tap can
    /// be promoted to a double tap.
    private var lastTap: (timestamp: Double, fingerCount: Int)?

    /// When a physical button was last pressed.
    ///
    /// A click is not a tap, so an episode containing a click is disqualified.
    /// This is a timestamp rather than a flag on the contact period: an earlier
    /// version marked the whole period as spent, which, with a hand resting on
    /// the mouse and therefore a period lasting minutes, killed every tap after
    /// the first click until the hand was lifted clear.
    private var lastClickTimestamp: Double?

    public init(tuning: RecognizerTuning = .default) {
        self.tuning = tuning
    }

    /// Discards any in-progress episode. Call this when the engine is disabled
    /// or the device disconnects, so stale state can't emit on the next frame.
    public func reset() {
        episode = nil
        lastTap = nil
        lastClickTimestamp = nil
    }

    /// Classifies a physical button press as a click gesture, using however
    /// many fingers are currently on the surface.
    ///
    /// Called by `GestureEngine` from `MouseButtonMonitor`, separately from the
    /// touch frame stream, because button events and touch frames arrive on
    /// different callbacks. Only presses produce gestures; releases are ignored.
    public func processButton(
        _ button: MouseButton,
        isDown: Bool,
        timestamp: Double
    ) -> GestureSpec? {
        guard isDown else { return nil }

        let fingers = episode?.contactCount ?? 0
        lastClickTimestamp = timestamp
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
    public func process(fingers: [MTFinger], timestamp: Double) -> GestureSpec? {
        let contacts = fingers.filter(\.isContact)
        let centroid = Self.centroid(of: contacts)

        guard var current = episode else {
            if !contacts.isEmpty {
                episode = Episode(
                    startTimestamp: timestamp,
                    lastTimestamp: timestamp,
                    baselineCentroid: centroid,
                    lastCentroid: centroid,
                    contactCount: contacts.count,
                    enteredByIncrease: true,
                    hasEmitted: false
                )
            }
            return nil
        }

        // A change in contact count ends the current episode.
        if contacts.count != current.contactCount {
            let finished = current
            let wentDown = contacts.count < current.contactCount

            episode = contacts.isEmpty
                ? nil
                : Episode(
                    startTimestamp: timestamp,
                    lastTimestamp: timestamp,
                    baselineCentroid: centroid,
                    lastCentroid: centroid,
                    contactCount: contacts.count,
                    enteredByIncrease: !wentDown,
                    hasEmitted: false
                )

            // Only a count going down completes a gesture. Going up is a hand
            // still settling onto the device.
            return wentDown ? classifyTap(finished, endedAt: timestamp) : nil
        }

        current.lastCentroid = centroid
        current.lastTimestamp = timestamp
        episode = current

        guard !current.hasEmitted else { return nil }

        let travel = Self.distance(from: current.baselineCentroid, to: centroid)
        let elapsed = timestamp - current.startTimestamp

        if travel >= tuning.swipeMinMovement {
            // Marked spent even when dropped for having too few fingers, so a
            // one-finger drag isn't re-tested on every subsequent frame.
            current.hasEmitted = true
            episode = current
            guard meetsMinimum(current.contactCount) else { return nil }
            let dx = Double(centroid.x - current.baselineCentroid.x)
            let dy = Double(centroid.y - current.baselineCentroid.y)
            return GestureSpec(
                fingerCount: current.contactCount,
                kind: Self.swipeKind(dx: dx, dy: dy)
            )
        }

        if elapsed >= tuning.holdMinDuration && travel <= tuning.holdMaxMovement {
            current.hasEmitted = true
            episode = current
            guard meetsMinimum(current.contactCount) else { return nil }
            return GestureSpec(fingerCount: current.contactCount, kind: .hold)
        }

        return nil
    }

    /// Decides whether a finished episode was a tap, and whether it pairs with
    /// the previous one into a double tap.
    private func classifyTap(_ finished: Episode, endedAt end: Double) -> GestureSpec? {
        guard !finished.hasEmitted else { return nil }

        // Only the peak of a contact ramp is a gesture. The counts passed
        // through while lifting are the tail of that same gesture. `lastTap` is
        // deliberately left alone here, so a pending double tap survives the
        // fingers coming off.
        guard finished.enteredByIncrease else { return nil }

        let travel = Self.distance(from: finished.baselineCentroid, to: finished.lastCentroid)
        let duration = finished.lastTimestamp - finished.startTimestamp

        guard duration <= tuning.tapMaxDuration, travel <= tuning.tapMaxMovement else {
            // An abandoned gesture shouldn't leave a half-finished double tap
            // armed for whatever the user does next.
            lastTap = nil
            return nil
        }

        let fingerCount = finished.contactCount
        guard meetsMinimum(fingerCount) else {
            lastTap = nil
            return nil
        }

        // A click is not a tap — but only the episode the click actually
        // happened during is disqualified. Suppressing on a time window instead
        // would randomly eat taps all day, because clicking is constant.
        if let lastClickTimestamp,
           lastClickTimestamp >= finished.startTimestamp,
           lastClickTimestamp <= end {
            lastTap = nil
            return nil
        }

        let liftTimestamp = finished.lastTimestamp

        // A second tap of the same finger count, soon enough after the first, is
        // a double tap.
        //
        // Note this emits `.tap` for the first and `.doubleTap` for the second;
        // it does not retroactively suppress the first. Suppressing it would
        // mean delaying every tap by the double-tap window, which makes single
        // taps feel laggy. Bind one or the other, not both, unless you want both.
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

    static func distance(from: MTPoint, to: MTPoint) -> Double {
        let dx = Double(to.x - from.x)
        let dy = Double(to.y - from.y)
        return (dx * dx + dy * dy).squareRoot()
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
