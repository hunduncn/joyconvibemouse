import XCTest
@testable import JoyConVibeCore

final class ClutchedPointerFrameBufferTests: XCTestCase {
    func testReleaseDiscardsTheLastActiveFrameInsteadOfEmittingItsJerk() {
        var buffer = ClutchedPointerFrameBuffer()
        let firstMotion = PointerDelta(dx: 8, dy: 1)
        let secondMotion = PointerDelta(dx: 6, dy: 0)
        let releaseJerk = PointerDelta(dx: 70, dy: 55)

        var emitted: [PointerDelta] = []
        emitted += buffer.process(frameDeltas: [], isActive: true)
        emitted += buffer.process(frameDeltas: [firstMotion], isActive: true)
        emitted += buffer.process(frameDeltas: [secondMotion], isActive: true)
        emitted += buffer.process(frameDeltas: [releaseJerk], isActive: true)
        emitted += buffer.process(frameDeltas: [], isActive: false)

        XCTAssertEqual(emitted, [firstMotion, secondMotion])
        XCTAssertFalse(emitted.contains(releaseJerk))
    }

    func testContinuousClutchEmitsEachConfirmedFrameInOrder() {
        var buffer = ClutchedPointerFrameBuffer()
        let first = PointerDelta(dx: 1, dy: 2)
        let second = PointerDelta(dx: 3, dy: 4)

        XCTAssertEqual(buffer.process(frameDeltas: [], isActive: true), [])
        XCTAssertEqual(buffer.process(frameDeltas: [first], isActive: true), [])
        XCTAssertEqual(buffer.process(frameDeltas: [second], isActive: true), [first])
        XCTAssertEqual(buffer.process(frameDeltas: [], isActive: true), [second])
    }

    func testResetDropsUnconfirmedMotion() {
        var buffer = ClutchedPointerFrameBuffer()
        let pending = PointerDelta(dx: 20, dy: 30)

        XCTAssertEqual(buffer.process(frameDeltas: [], isActive: true), [])
        XCTAssertEqual(buffer.process(frameDeltas: [pending], isActive: true), [])
        buffer.reset()
        XCTAssertEqual(buffer.process(frameDeltas: [], isActive: true), [])
    }

    func testActivationFrameJoltIsNeverReplayedAfterPressingClutch() {
        var buffer = ClutchedPointerFrameBuffer()
        let pressJolt = PointerDelta(dx: 70, dy: 55)
        let deliberateMotion = PointerDelta(dx: 4, dy: 1)

        XCTAssertEqual(
            buffer.process(frameDeltas: [pressJolt], isActive: true),
            []
        )
        XCTAssertEqual(
            buffer.process(frameDeltas: [deliberateMotion], isActive: true),
            []
        )
        XCTAssertEqual(
            buffer.process(frameDeltas: [], isActive: true),
            [deliberateMotion]
        )
    }
}
