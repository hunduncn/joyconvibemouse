import XCTest
@testable import JoyConVibeCore

final class PointerMotionPacingPlanTests: XCTestCase {
    func testJoyConSubsamplesAreSpreadAcrossTheirPhysicalSampleInterval() {
        let deltas = [
            PointerDelta(dx: 1, dy: 0),
            PointerDelta(dx: 2, dy: 0),
            PointerDelta(dx: 3, dy: 0)
        ]

        let steps = PointerMotionPacingPlan.steps(for: deltas)

        XCTAssertEqual(steps.map(\.delta), deltas)
        XCTAssertEqual(steps.map(\.delay), [0, 0.005, 0.010])
    }
}
