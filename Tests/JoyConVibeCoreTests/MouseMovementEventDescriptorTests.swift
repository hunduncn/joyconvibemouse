import XCTest
@testable import JoyConVibeCore

final class MouseMovementEventDescriptorTests: XCTestCase {
    func testMovementCarriesBothAbsoluteDestinationAndRelativeMouseDelta() {
        let descriptor = MouseMovementEventDescriptor(
            currentX: 400,
            currentY: 300,
            delta: PointerDelta(dx: 120, dy: -80)
        )

        XCTAssertEqual(descriptor.destinationX, 520)
        XCTAssertEqual(descriptor.destinationY, 220)
        XCTAssertEqual(descriptor.relativeDeltaX, 120)
        XCTAssertEqual(descriptor.relativeDeltaY, -80)
    }
}
