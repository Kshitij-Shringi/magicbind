import XCTest

@testable import MagicBindCore

/// Drives `GestureRecognizer` with synthetic `MTFinger` frames.
///
/// The recognizer takes its timestamps from the caller, so these tests are
/// fully deterministic — no sleeping, no wall clock, no device.
final class GestureRecognizerTests: XCTestCase {
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

    // MARK: - Helpers

    /// Builds a frame of `count` fingers, spread apart so their centroid sits
    /// at (`x`, `y`).
    private func frame(
        fingerCount count: Int,
        x: Float,
        y: Float,
        timestamp: Double
    ) -> [MTFinger] {
        // Offsets are symmetric around zero, so the centroid is exactly (x, y)
        // regardless of finger count.
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

    /// Feeds a sequence of frames in and collects everything emitted.
    private func feed(_ frames: [(fingers: [MTFinger], timestamp: Double)]) -> [GestureSpec] {
        frames.compactMap { recognizer.process(fingers: $0.fingers, timestamp: $0.timestamp) }
    }

    // MARK: - Taps

    func testThreeFingerTapEmitsThreeFingerTapSpec() {
        let emitted = feed([
            (frame(fingerCount: 3, x: 0.5, y: 0.5, timestamp: 0.00), 0.00),
            (frame(fingerCount: 3, x: 0.5, y: 0.5, timestamp: 0.05), 0.05),
            (frame(fingerCount: 3, x: 0.5, y: 0.5, timestamp: 0.09), 0.09),
            ([], 0.12)
        ])

        XCTAssertEqual(emitted, [GestureSpec(fingerCount: 3, kind: .tap)])
    }

    func testTapSurvivesFingersLandingOneAtATime() {
        // Real hardware reports 1, then 2, then 3 contacts as the fingers
        // settle. The centroid jumps each time, and that must not be mistaken
        // for a swipe.
        let emitted = feed([
            (frame(fingerCount: 1, x: 0.30, y: 0.50, timestamp: 0.00), 0.00),
            (frame(fingerCount: 2, x: 0.40, y: 0.50, timestamp: 0.02), 0.02),
            (frame(fingerCount: 3, x: 0.50, y: 0.50, timestamp: 0.04), 0.04),
            (frame(fingerCount: 3, x: 0.50, y: 0.50, timestamp: 0.08), 0.08),
            ([], 0.11)
        ])

        XCTAssertEqual(emitted, [GestureSpec(fingerCount: 3, kind: .tap)])
    }

    func testContactHeldTooLongIsNotATap() {
        let tooLong = tuning.tapMaxDuration + 0.1
        let emitted = feed([
            (frame(fingerCount: 3, x: 0.5, y: 0.5, timestamp: 0.0), 0.0),
            (frame(fingerCount: 3, x: 0.5, y: 0.5, timestamp: tooLong), tooLong),
            ([], tooLong + 0.02)
        ])

        XCTAssertEqual(emitted, [])
    }

    func testFingersThatNeverMakeContactAreIgnored() {
        let hovering = [
            MTFinger.contact(identifier: 1, x: 0.5, y: 0.5, state: .hoverInRange),
            MTFinger.contact(identifier: 2, x: 0.6, y: 0.5, state: .hoverInRange)
        ]

        XCTAssertNil(recognizer.process(fingers: hovering, timestamp: 0.0))
        XCTAssertNil(recognizer.process(fingers: [], timestamp: 0.05))
    }

    // MARK: - Swipes

    func testFourFingerSwipeUpEmitsFourFingerSwipeUpSpec() {
        // Normalized y increases toward the far edge, so climbing y is "up".
        // Total travel is 0.15, comfortably past the 0.08 swipe threshold.
        let emitted = feed([
            (frame(fingerCount: 4, x: 0.50, y: 0.30, timestamp: 0.00), 0.00),
            (frame(fingerCount: 4, x: 0.50, y: 0.34, timestamp: 0.03), 0.03),
            (frame(fingerCount: 4, x: 0.50, y: 0.39, timestamp: 0.06), 0.06),
            (frame(fingerCount: 4, x: 0.50, y: 0.45, timestamp: 0.09), 0.09),
            ([], 0.12)
        ])

        XCTAssertEqual(emitted, [GestureSpec(fingerCount: 4, kind: .swipeUp)])
    }

    func testSwipeEmitsExactlyOncePerContactSession() {
        // Once a swipe fires, the rest of the session stays silent — no
        // repeat fire as the fingers keep travelling, and no tap on release.
        let emitted = feed([
            (frame(fingerCount: 4, x: 0.5, y: 0.20, timestamp: 0.00), 0.00),
            (frame(fingerCount: 4, x: 0.5, y: 0.40, timestamp: 0.05), 0.05),
            (frame(fingerCount: 4, x: 0.5, y: 0.60, timestamp: 0.10), 0.10),
            (frame(fingerCount: 4, x: 0.5, y: 0.80, timestamp: 0.15), 0.15),
            ([], 0.18)
        ])

        XCTAssertEqual(emitted, [GestureSpec(fingerCount: 4, kind: .swipeUp)])
    }

    func testSwipeDirectionsUseTheDominantAxis() {
        let cases: [(dx: Float, dy: Float, expected: GestureKind)] = [
            (0.00, 0.15, .swipeUp),
            (0.00, -0.15, .swipeDown),
            (0.15, 0.00, .swipeRight),
            (-0.15, 0.00, .swipeLeft),
            // Mostly horizontal with a little vertical drift stays horizontal.
            (0.15, 0.04, .swipeRight)
        ]

        for testCase in cases {
            let recognizer = GestureRecognizer(tuning: tuning)
            let start = recognizer.process(
                fingers: frame(fingerCount: 2, x: 0.5, y: 0.5, timestamp: 0),
                timestamp: 0
            )
            XCTAssertNil(start)

            let moved = recognizer.process(
                fingers: frame(
                    fingerCount: 2,
                    x: 0.5 + testCase.dx,
                    y: 0.5 + testCase.dy,
                    timestamp: 0.05
                ),
                timestamp: 0.05
            )

            XCTAssertEqual(
                moved,
                GestureSpec(fingerCount: 2, kind: testCase.expected),
                "dx \(testCase.dx), dy \(testCase.dy)"
            )
        }
    }

    func testMovementBelowSwipeThresholdIsStillATap() {
        let nudge = Float(tuning.tapMaxMovement) / 2
        let emitted = feed([
            (frame(fingerCount: 2, x: 0.50, y: 0.50, timestamp: 0.00), 0.00),
            (frame(fingerCount: 2, x: 0.50 + nudge, y: 0.50, timestamp: 0.06), 0.06),
            ([], 0.09)
        ])

        XCTAssertEqual(emitted, [GestureSpec(fingerCount: 2, kind: .tap)])
    }

    // MARK: - Holds

    func testStationaryContactPastHoldThresholdEmitsHold() {
        let past = tuning.holdMinDuration + 0.05
        let emitted = feed([
            (frame(fingerCount: 2, x: 0.5, y: 0.5, timestamp: 0.0), 0.0),
            (frame(fingerCount: 2, x: 0.5, y: 0.5, timestamp: 0.2), 0.2),
            (frame(fingerCount: 2, x: 0.5, y: 0.5, timestamp: past), past),
            (frame(fingerCount: 2, x: 0.5, y: 0.5, timestamp: past + 0.1), past + 0.1),
            ([], past + 0.2)
        ])

        XCTAssertEqual(emitted, [GestureSpec(fingerCount: 2, kind: .hold)])
    }

    // MARK: - Session lifecycle

    func testResetDiscardsAnInProgressSession() {
        _ = recognizer.process(
            fingers: frame(fingerCount: 3, x: 0.5, y: 0.5, timestamp: 0),
            timestamp: 0
        )
        recognizer.reset()

        XCTAssertNil(recognizer.process(fingers: [], timestamp: 0.05))
    }

    func testConsecutiveTapsEachEmit() {
        let emitted = feed([
            (frame(fingerCount: 3, x: 0.5, y: 0.5, timestamp: 0.00), 0.00),
            ([], 0.05),
            (frame(fingerCount: 3, x: 0.5, y: 0.5, timestamp: 0.30), 0.30),
            ([], 0.35)
        ])

        XCTAssertEqual(
            emitted,
            [
                GestureSpec(fingerCount: 3, kind: .tap),
                GestureSpec(fingerCount: 3, kind: .tap)
            ]
        )
    }

    // MARK: - Geometry helpers

    func testCentroidAveragesEveryContact() {
        let fingers = [
            MTFinger.contact(identifier: 1, x: 0.0, y: 0.0),
            MTFinger.contact(identifier: 2, x: 1.0, y: 0.0),
            MTFinger.contact(identifier: 3, x: 0.5, y: 0.6)
        ]

        let centroid = GestureRecognizer.centroid(of: fingers)

        XCTAssertEqual(centroid.x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(centroid.y, 0.2, accuracy: 0.0001)
    }
}
