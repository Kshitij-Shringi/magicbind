import Foundation
import XCTest

@testable import MagicBindCore

/// Tests for the two gesture kinds added alongside the Options+-style UI:
/// physical clicks and double taps.
final class ClickAndDoubleTapTests: XCTestCase {
    private var recognizer: GestureRecognizer!
    private var tuning: RecognizerTuning!

    override func setUp() {
        super.setUp()
        tuning = .default
        recognizer = GestureRecognizer(tuning: tuning)
    }

    override func tearDown() {
        recognizer = nil
        tuning = nil
        super.tearDown()
    }

    private func frame(
        fingerCount count: Int,
        x: Float = 0.5,
        y: Float = 0.5,
        timestamp: Double
    ) -> [MTFinger] {
        let spread: Float = 0.04
        let mid = Float(count - 1) / 2
        return (0..<count).map { index in
            MTFinger.contact(
                identifier: Int32(index + 1),
                x: x + (Float(index) - mid) * spread,
                y: y,
                timestamp: timestamp
            )
        }
    }

    // MARK: - Clicks

    func testBareClickWithNoFingersOnTheSurface() {
        let gesture = recognizer.processButton(.left, isDown: true, timestamp: 0)

        XCTAssertEqual(
            gesture,
            GestureSpec(fingerCount: 0, kind: .click, button: .left)
        )
    }

    func testClickCarriesTheCurrentFingerCount() {
        _ = recognizer.process(fingers: frame(fingerCount: 2, timestamp: 0), timestamp: 0)

        let gesture = recognizer.processButton(.left, isDown: true, timestamp: 0.02)

        XCTAssertEqual(
            gesture,
            GestureSpec(fingerCount: 2, kind: .click, button: .left)
        )
    }

    func testButtonReleaseEmitsNothing() {
        XCTAssertNil(recognizer.processButton(.left, isDown: false, timestamp: 0))
        XCTAssertNil(recognizer.processButton(.right, isDown: false, timestamp: 0.1))
    }

    func testEachButtonIsADistinctGesture() {
        let left = recognizer.processButton(.left, isDown: true, timestamp: 0)
        let right = recognizer.processButton(.right, isDown: true, timestamp: 0.5)
        let middle = recognizer.processButton(.middle, isDown: true, timestamp: 1.0)

        XCTAssertEqual(left?.button, .left)
        XCTAssertEqual(right?.button, .right)
        XCTAssertEqual(middle?.button, .middle)
        XCTAssertNotEqual(left, right)
    }

    func testClickSuppressesTheTapThatWouldOtherwiseFireOnLift() {
        // Fingers down, then a real click, then lift. The user clicked — they
        // did not tap — so no tap should follow.
        _ = recognizer.process(fingers: frame(fingerCount: 2, timestamp: 0), timestamp: 0)
        let click = recognizer.processButton(.left, isDown: true, timestamp: 0.03)
        _ = recognizer.processButton(.left, isDown: false, timestamp: 0.08)
        let onLift = recognizer.process(fingers: [], timestamp: 0.10)

        XCTAssertEqual(click?.kind, .click)
        XCTAssertNil(onLift, "a click must not also produce a tap")
    }

    // MARK: - Double taps

    func testTwoQuickTapsProduceTapThenDoubleTap() {
        var emitted: [GestureSpec] = []
        let frames: [([MTFinger], Double)] = [
            (frame(fingerCount: 3, timestamp: 0.00), 0.00),
            ([], 0.05),
            (frame(fingerCount: 3, timestamp: 0.20), 0.20),
            ([], 0.25)
        ]
        for (fingers, timestamp) in frames {
            if let gesture = recognizer.process(fingers: fingers, timestamp: timestamp) {
                emitted.append(gesture)
            }
        }

        // The first tap is not retroactively suppressed — see the note in
        // GestureRecognizer.endSession about why delaying every tap is worse.
        XCTAssertEqual(
            emitted,
            [
                GestureSpec(fingerCount: 3, kind: .tap),
                GestureSpec(fingerCount: 3, kind: .doubleTap)
            ]
        )
    }

    func testTapsTooFarApartAreTwoSingleTaps() {
        let gap = tuning.effectiveDoubleTapMaxInterval + 0.2
        var emitted: [GestureSpec] = []
        let frames: [([MTFinger], Double)] = [
            (frame(fingerCount: 3, timestamp: 0.0), 0.0),
            ([], 0.03),
            (frame(fingerCount: 3, timestamp: gap), gap),
            ([], gap + 0.03)
        ]
        for (fingers, timestamp) in frames {
            if let gesture = recognizer.process(fingers: fingers, timestamp: timestamp) {
                emitted.append(gesture)
            }
        }

        XCTAssertEqual(emitted.map(\.kind), [.tap, .tap])
    }

    func testDifferentFingerCountsDoNotFormADoubleTap() {
        var emitted: [GestureSpec] = []
        let frames: [([MTFinger], Double)] = [
            (frame(fingerCount: 2, timestamp: 0.00), 0.00),
            ([], 0.03),
            (frame(fingerCount: 3, timestamp: 0.15), 0.15),
            ([], 0.18)
        ]
        for (fingers, timestamp) in frames {
            if let gesture = recognizer.process(fingers: fingers, timestamp: timestamp) {
                emitted.append(gesture)
            }
        }

        XCTAssertEqual(
            emitted,
            [
                GestureSpec(fingerCount: 2, kind: .tap),
                GestureSpec(fingerCount: 3, kind: .tap)
            ]
        )
    }

    func testThreeQuickTapsDoNotChainIntoASecondDoubleTap() {
        // After a double tap resolves, the counter resets, so the third tap is
        // a fresh single tap rather than immediately doubling again.
        var emitted: [GestureSpec] = []
        let frames: [([MTFinger], Double)] = [
            (frame(fingerCount: 3, timestamp: 0.00), 0.00),
            ([], 0.03),
            (frame(fingerCount: 3, timestamp: 0.12), 0.12),
            ([], 0.15),
            (frame(fingerCount: 3, timestamp: 0.24), 0.24),
            ([], 0.27)
        ]
        for (fingers, timestamp) in frames {
            if let gesture = recognizer.process(fingers: fingers, timestamp: timestamp) {
                emitted.append(gesture)
            }
        }

        XCTAssertEqual(emitted.map(\.kind), [.tap, .doubleTap, .tap])
    }

    func testAClickBetweenTwoTapsBreaksTheDoubleTap() {
        var emitted: [GestureSpec] = []

        let firstTouch = frame(fingerCount: 3, timestamp: 0)
        if let first = recognizer.process(fingers: firstTouch, timestamp: 0) {
            emitted.append(first)
        }
        if let lift = recognizer.process(fingers: [], timestamp: 0.03) {
            emitted.append(lift)
        }
        _ = recognizer.processButton(.left, isDown: true, timestamp: 0.06)
        if let second = recognizer.process(
            fingers: frame(fingerCount: 3, timestamp: 0.12),
            timestamp: 0.12
        ) {
            emitted.append(second)
        }
        if let lift = recognizer.process(fingers: [], timestamp: 0.15) {
            emitted.append(lift)
        }

        XCTAssertEqual(emitted.map(\.kind), [.tap, .tap])
    }

    func testAbandonedGestureClearsPendingDoubleTap() {
        // A tap, then a long press that isn't a tap, then a tap: the last tap
        // must not pair with the first.
        var emitted: [GestureSpec] = []
        let tooLong = tuning.tapMaxDuration + 0.1
        let frames: [([MTFinger], Double)] = [
            (frame(fingerCount: 3, timestamp: 0.0), 0.0),
            ([], 0.02),
            (frame(fingerCount: 3, timestamp: 0.05), 0.05),
            (frame(fingerCount: 3, timestamp: 0.05 + tooLong), 0.05 + tooLong),
            ([], 0.07 + tooLong),
            (frame(fingerCount: 3, timestamp: 0.09 + tooLong), 0.09 + tooLong),
            ([], 0.11 + tooLong)
        ]
        for (fingers, timestamp) in frames {
            if let gesture = recognizer.process(fingers: fingers, timestamp: timestamp) {
                emitted.append(gesture)
            }
        }

        XCTAssertEqual(emitted.map(\.kind), [.tap, .tap])
    }

    func testResetClearsPendingDoubleTap() {
        _ = recognizer.process(fingers: frame(fingerCount: 3, timestamp: 0), timestamp: 0)
        _ = recognizer.process(fingers: [], timestamp: 0.03)

        recognizer.reset()

        _ = recognizer.process(fingers: frame(fingerCount: 3, timestamp: 0.10), timestamp: 0.10)
        let second = recognizer.process(fingers: [], timestamp: 0.13)

        XCTAssertEqual(second?.kind, .tap)
    }
}
