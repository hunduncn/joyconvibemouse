import XCTest
@testable import JoyConVibeCore

final class KeyboardEventPlanTests: XCTestCase {
    func testRepeatedFunctionTapsFullyReleaseFnBetweenPresses() {
        let tap = KeyboardEventPlan.tap(for: .function)
        let repeated = tap + tap

        XCTAssertEqual(
            repeated,
            [
                .init(isDown: true, functionModifierIsDown: true),
                .init(isDown: false, functionModifierIsDown: false),
                .init(isDown: true, functionModifierIsDown: true),
                .init(isDown: false, functionModifierIsDown: false)
            ]
        )
    }

    func testOrdinaryKeyTapNeverAddsFunctionModifier() {
        XCTAssertEqual(
            KeyboardEventPlan.tap(for: .returnKey),
            [
                .init(isDown: true, functionModifierIsDown: false),
                .init(isDown: false, functionModifierIsDown: false)
            ]
        )
    }
}
