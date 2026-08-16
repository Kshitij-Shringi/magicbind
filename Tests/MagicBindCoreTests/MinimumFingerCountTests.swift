import Foundation
import XCTest

@testable import MagicBindCore

/// One finger on a mouse is just holding the mouse. Measured on real hardware:
/// simply moving a Magic Mouse produced a continuous stream of `1-finger Hold`
/// and `1-finger Swipe` recognitions.
final class MinimumFingerCountTests: XCTestCase {
    private var recognizer: GestureRecognizer!

    override func setUp() {
        super.setUp()
        recognizer = GestureRecognizer(tuning: .default)
    }

    override func tearDown() {
        recognizer = nil
        super.tearDown()
    }

    private func frame(_ count: Int, x: Float = 0.5, y: Float = 0.5) -> [MTFinger] {
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

    private func feed(_ steps: [([MTFinger], Double)]) -> [GestureSpec] {
        steps.compactMap { recognizer.process(fingers: $0.0, timestamp: $0.1) }
    }

    // MARK: - Default is 2

    func testDefaultMinimumIsTwo() {
        XCTAssertEqual(RecognizerTuning.default.effectiveMinimumFingerCount, 2)
    }

    func testOneFingerTapIsIgnored() {
        let emitted = feed([(frame(1), 0.0), ([], 0.05)])

        XCTAssertEqual(emitted, [])
    }

    func testOneFingerHoldIsIgnored() {
        let past = RecognizerTuning.default.holdMinDuration + 0.1
        let emitted = feed([(frame(1), 0.0), (frame(1), past), ([], past + 0.1)])

        XCTAssertEqual(emitted, [], "moving the mouse must not register as a hold")
    }

    func testOneFingerSwipeIsIgnored() {
        let emitted = feed([
            (frame(1, y: 0.20), 0.00),
            (frame(1, y: 0.45), 0.05),
            (frame(1, y: 0.70), 0.10),
            ([], 0.13)
        ])

        XCTAssertEqual(emitted, [], "dragging the mouse must not register as a swipe")
    }

    func testTwoFingerGesturesStillWork() {
        XCTAssertEqual(
            feed([(frame(2), 0.0), ([], 0.05)]),
            [GestureSpec(fingerCount: 2, kind: .tap)]
        )
    }

    func testThreeFingerGesturesStillWork() {
        XCTAssertEqual(
            feed([(frame(3), 0.0), ([], 0.05)]),
            [GestureSpec(fingerCount: 3, kind: .tap)]
        )
    }

    // MARK: - Configurable

    func testLoweringTheMinimumReenablesOneFinger() {
        recognizer.tuning.minimumFingerCount = 1

        XCTAssertEqual(
            feed([(frame(1), 0.0), ([], 0.05)]),
            [GestureSpec(fingerCount: 1, kind: .tap)]
        )
    }

    func testRaisingTheMinimumSuppressesLowerCounts() {
        recognizer.tuning.minimumFingerCount = 4

        XCTAssertEqual(feed([(frame(3), 0.0), ([], 0.05)]), [])
        XCTAssertEqual(
            feed([(frame(4), 1.0), ([], 1.05)]),
            [GestureSpec(fingerCount: 4, kind: .tap)]
        )
    }

    func testMinimumIsClampedToSaneValues() {
        var tuning = RecognizerTuning.default
        tuning.minimumFingerCount = 0
        XCTAssertEqual(tuning.effectiveMinimumFingerCount, 1)
        tuning.minimumFingerCount = 99
        XCTAssertEqual(tuning.effectiveMinimumFingerCount, 5)
    }

    func testOlderConfigsWithoutTheFieldGetTheSafeDefault() throws {
        let legacy = """
            {"tapMaxDuration":0.25,"tapMaxMovement":0.03,"swipeMinMovement":0.08,
             "holdMinDuration":0.5,"holdMaxMovement":0.03}
            """
        let decoded = try ConfigStore.makeDecoder()
            .decode(RecognizerTuning.self, from: Data(legacy.utf8))

        XCTAssertNil(decoded.minimumFingerCount)
        XCTAssertEqual(decoded.effectiveMinimumFingerCount, 2)
    }

    // MARK: - Clicks are deliberate

    func testClicksAreNotGatedByTheMinimum() {
        // A click is an explicit act, never an accident of gripping the device,
        // so a bare or one-finger click must still be bindable.
        XCTAssertEqual(
            recognizer.processButton(.left, isDown: true, timestamp: 0),
            GestureSpec(fingerCount: 0, kind: .click, button: .left)
        )

        _ = recognizer.process(fingers: frame(1), timestamp: 1.0)
        XCTAssertEqual(
            recognizer.processButton(.left, isDown: true, timestamp: 1.02)?.fingerCount,
            1
        )
    }

    // MARK: - No re-testing mid-drag

    func testASuppressedSwipeDoesNotReEvaluateOnLaterFrames() {
        // Once a one-finger drag is rejected the session is finished; it must not
        // re-test on every subsequent frame and fire the moment a second finger
        // happens to land.
        let emitted = feed([
            (frame(1, y: 0.20), 0.00),
            (frame(1, y: 0.50), 0.05),
            (frame(1, y: 0.80), 0.10),
            (frame(1, y: 0.90), 0.15),
            ([], 0.20)
        ])

        XCTAssertEqual(emitted, [])
    }
}
