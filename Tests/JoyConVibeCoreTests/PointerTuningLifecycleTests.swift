import XCTest
@testable import JoyConVibeCore

final class PointerTuningLifecycleTests: XCTestCase {
    func testResetIsRequestedExactlyWhenSliderEditingEnds() {
        var lifecycle = PointerTuningLifecycle()

        XCTAssertFalse(lifecycle.update(isEditing: true))
        XCTAssertFalse(lifecycle.update(isEditing: true))
        XCTAssertTrue(lifecycle.update(isEditing: false))
        XCTAssertFalse(lifecycle.update(isEditing: false))
    }
}
