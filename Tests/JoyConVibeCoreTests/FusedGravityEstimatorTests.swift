import XCTest
@testable import JoyConVibeCore

final class FusedGravityEstimatorTests: XCTestCase {
    func testLinearAccelerationDoesNotInstantlyReplaceGravity() {
        var estimator = FusedGravityEstimator()
        _ = estimator.update(
            angularVelocity: .zero,
            acceleration: Vector3(x: 0, y: 1, z: 0)
        )

        let gravity = estimator.update(
            angularVelocity: .zero,
            acceleration: Vector3(x: 1, y: 0, z: 0)
        )

        XCTAssertLessThan(gravity.y, -0.99)
        XCTAssertLessThan(abs(gravity.x), 0.02)
    }

    func testGyroPropagationTracksVerticalToFlatTiltWithoutAccelerometer() {
        var estimator = FusedGravityEstimator()
        _ = estimator.update(
            angularVelocity: .zero,
            acceleration: Vector3(x: 0, y: 1, z: 0)
        )

        var gravity = Vector3.zero
        for _ in 0..<200 {
            gravity = estimator.update(
                angularVelocity: Vector3(x: 90, y: 0, z: 0),
                acceleration: .zero
            )
        }

        XCTAssertEqual(gravity.y, 0, accuracy: 0.02)
        XCTAssertEqual(abs(gravity.z), 1, accuracy: 0.02)
    }
}
