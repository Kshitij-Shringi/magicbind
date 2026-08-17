import Foundation
import XCTest

@testable import MagicBindCore

/// Gestures made while a hand rests on the device.
///
/// This is how a mouse is actually held, and it used to be completely broken. An
/// earlier design only evaluated a gesture once *every* finger left the surface.
/// On a Magic Mouse a finger never leaves, so the contact period was minutes
/// long, its duration always failed the tap window, and taps never fired at all.
/// It appeared to work only when the hand was lifted clear between attempts —
/// which is what testing looks like, not what use looks like.
final class RestingHandTests: XCTestCase {
    private var recognizer: GestureRecognizer!

    override func setUp() {
        super.setUp()
        recognizer = GestureRecognizer(tuning: .default)
    }

    override func tearDown() {
        recognizer = nil
        super.tearDown()
    }

    private func contact(_ count: Int, x: Float = 0.5, y: Float = 0.5) -> [MTFinger] {
        let spread: Float = 0.04
        let mid = Float(count - 1) / 2
        return (0..<count).map { index in
            MTFinger.contact(
                identifier: Int32(index + 1),
                x: x + (Float(index) - mid) * spread,
                y: y
            )
        }
    }

    /// Rests `count` fingers on the device for `seconds`, as holding it does.
    private func rest(_ count: Int, seconds: Double, from start: Double) -> Double {
        var time = start
        while time < start + seconds {
            _ = recognizer.process(fingers: contact(count), timestamp: time)
            time += 0.1
        }
        return time
    }

    // MARK: - The bug that made middle click stop working

    func testTapWorksWithAFingerAlreadyRestingOnTheDevice() {
        // Hand on the mouse for five seconds, then tap a second finger.
        var time = rest(1, seconds: 5, from: 0)

        _ = recognizer.process(fingers: contact(2), timestamp: time)
        time += 0.05
        _ = recognizer.process(fingers: contact(2), timestamp: time)
        time += 0.05
        let onRelease = recognizer.process(fingers: contact(1), timestamp: time)

        XCTAssertEqual(
            onRelease,
            GestureSpec(fingerCount: 2, kind: .tap),
            "a two-finger tap must fire while a finger rests on the device"
        )
    }

    func testTapWorksAfterMinutesOfHolding() {
        // Duration is measured from when the newest finger landed, so how long
        // the hand has been there is irrelevant.
        var time = rest(1, seconds: 120, from: 0)

        _ = recognizer.process(fingers: contact(3), timestamp: time)
        time += 0.06
        let onRelease = recognizer.process(fingers: contact(1), timestamp: time)

        XCTAssertEqual(onRelease, GestureSpec(fingerCount: 3, kind: .tap))
    }

    func testRepeatedTapsAllFireWithoutLiftingTheHand() {
        var time = rest(1, seconds: 1, from: 0)
        var emitted: [GestureKind] = []

        // Well apart, so they don't pair into double taps.
        for _ in 0..<4 {
            _ = recognizer.process(fingers: contact(2), timestamp: time)
            time += 0.05
            if let gesture = recognizer.process(fingers: contact(1), timestamp: time) {
                emitted.append(gesture.kind)
            }
            time = rest(1, seconds: 1, from: time)
        }

        XCTAssertEqual(emitted, [.tap, .tap, .tap, .tap])
    }

    // MARK: - Clicking must not disable tapping

    func testTapWorksAfterAClickWithoutLiftingTheHand() {
        // A click used to mark the whole contact period spent, so with a hand
        // resting every tap after the first click was dead.
        var time = rest(1, seconds: 1, from: 0)

        _ = recognizer.processButton(.left, isDown: true, timestamp: time)
        _ = recognizer.processButton(.left, isDown: false, timestamp: time + 0.05)
        time += 0.3

        _ = recognizer.process(fingers: contact(2), timestamp: time)
        time += 0.05
        let onRelease = recognizer.process(fingers: contact(1), timestamp: time)

        XCTAssertEqual(onRelease, GestureSpec(fingerCount: 2, kind: .tap))
    }

    func testManyClicksDoNotDisableTapping() {
        var time = rest(1, seconds: 0.5, from: 0)
        for _ in 0..<10 {
            _ = recognizer.processButton(.left, isDown: true, timestamp: time)
            _ = recognizer.processButton(.left, isDown: false, timestamp: time + 0.02)
            time += 0.2
        }

        _ = recognizer.process(fingers: contact(2), timestamp: time)
        time += 0.05
        let onRelease = recognizer.process(fingers: contact(1), timestamp: time)

        XCTAssertEqual(onRelease, GestureSpec(fingerCount: 2, kind: .tap))
    }

    func testAClickDuringAnEpisodeStillSuppressesThatEpisodesTap() {
        // The suppression that should survive: the click happened *during* this
        // contact, so this contact was a click and not a tap.
        _ = recognizer.process(fingers: contact(2), timestamp: 0.0)
        _ = recognizer.processButton(.left, isDown: true, timestamp: 0.02)
        let onRelease = recognizer.process(fingers: contact(1), timestamp: 0.05)

        XCTAssertNil(onRelease, "a contact period containing a click is not a tap")
    }

    // MARK: - Fingers land one at a time

    func testBuildingUpToThreeFingersEmitsOnlyTheThreeFingerTap() {
        // Fingers rarely land together. Going 1 -> 2 -> 3 must not emit an
        // intermediate two-finger tap on the way up.
        var emitted: [GestureSpec] = []
        let steps: [(Int, Double)] = [(1, 0.00), (2, 0.02), (3, 0.04), (3, 0.08)]
        for (count, time) in steps {
            if let gesture = recognizer.process(fingers: contact(count), timestamp: time) {
                emitted.append(gesture)
            }
        }
        if let gesture = recognizer.process(fingers: [], timestamp: 0.11) {
            emitted.append(gesture)
        }

        XCTAssertEqual(emitted, [GestureSpec(fingerCount: 3, kind: .tap)])
    }

    func testLiftingFingersOneAtATimeEmitsOnlyTheHighestCount() {
        // Coming back down 3 -> 2 -> 1 -> 0 should give the three-finger tap and
        // then nothing, not a cascade of smaller taps.
        var emitted: [GestureSpec] = []
        let steps: [(Int, Double)] = [(3, 0.00), (3, 0.05), (2, 0.08), (1, 0.10)]
        for (count, time) in steps {
            if let gesture = recognizer.process(fingers: contact(count), timestamp: time) {
                emitted.append(gesture)
            }
        }
        if let gesture = recognizer.process(fingers: [], timestamp: 0.12) {
            emitted.append(gesture)
        }

        XCTAssertEqual(
            emitted.map(\.kind),
            [.tap],
            "got \(emitted.map(\.displayName))"
        )
        XCTAssertEqual(emitted.first?.fingerCount, 3)
    }

    // MARK: - Swipes and holds with a resting hand

    func testSwipeWorksWithAFingerAlreadyResting() {
        var time = rest(1, seconds: 2, from: 0)

        _ = recognizer.process(fingers: contact(2, y: 0.30), timestamp: time)
        time += 0.05
        let swipe = recognizer.process(fingers: contact(2, y: 0.50), timestamp: time)

        XCTAssertEqual(swipe, GestureSpec(fingerCount: 2, kind: .swipeUp))
    }

    func testHoldWorksWithAFingerAlreadyResting() {
        var time = rest(1, seconds: 2, from: 0)
        let start = time

        _ = recognizer.process(fingers: contact(3), timestamp: time)
        var hold: GestureSpec?
        while time < start + 0.7 {
            time += 0.1
            if let gesture = recognizer.process(fingers: contact(3), timestamp: time) {
                hold = gesture
            }
        }

        XCTAssertEqual(hold, GestureSpec(fingerCount: 3, kind: .hold))
    }

    func testRestingOneFingerAloneNeverEmitsAnything() {
        // The whole point of the minimum: holding the mouse is not a gesture.
        var emitted: [GestureSpec] = []
        var time = 0.0
        while time < 10 {
            if let gesture = recognizer.process(fingers: contact(1), timestamp: time) {
                emitted.append(gesture)
            }
            time += 0.1
        }

        XCTAssertEqual(emitted, [], "got \(emitted.map(\.displayName))")
    }
}
