import XCTest
@testable import JoyConVibeCore

final class GyroPointerEngineTests: XCTestCase {
    func testRightJoyConRawAxesUseSeparateGyroAndAccelerationContracts() {
        let raw = Vector3(x: 1, y: 2, z: 3)

        XCTAssertEqual(
            JoyConIMUCoordinateSpace.angularVelocity(from: raw),
            Vector3(x: -2, y: 3, z: 1)
        )
        XCTAssertEqual(
            JoyConIMUCoordinateSpace.acceleration(from: raw),
            Vector3(x: -2, y: 3, z: -1)
        )
    }

    func testRequiresStationaryCalibrationBeforeMoving() {
        var engine = GyroPointerEngine()
        let sample = rawSample(bodyRate: .zero)

        for _ in 0..<159 {
            XCTAssertNil(engine.process(
                sample: sample,
                isActive: true,
                isPrecision: false,
                settings: PointerSettings()
            ))
        }
        XCTAssertNotEqual(engine.calibrationState, .ready)

        XCTAssertNil(engine.process(
            sample: sample,
            isActive: true,
            isPrecision: false,
            settings: PointerSettings()
        ))
        XCTAssertEqual(engine.calibrationState, .ready)
    }

    func testClutchAndSLPrecisionScaling() throws {
        var normal = calibratedEngine()
        var precise = calibratedEngine()
        let sample = rawSample(bodyRate: Vector3(x: 0, y: 60, z: 0))
        let settings = PointerSettings(precisionMultiplier: 0.35)

        XCTAssertNil(normal.process(
            sample: sample,
            isActive: false,
            isPrecision: false,
            settings: settings
        ))

        let normalDelta = try XCTUnwrap(normal.process(
            sample: sample,
            isActive: true,
            isPrecision: false,
            settings: settings
        ))
        let preciseDelta = try XCTUnwrap(precise.process(
            sample: sample,
            isActive: true,
            isPrecision: true,
            settings: settings
        ))

        XCTAssertGreaterThan(abs(normalDelta.dx), 0)
        XCTAssertEqual(preciseDelta.dx / normalDelta.dx, 0.35, accuracy: 0.001)
        XCTAssertEqual(normalDelta.dy, 0, accuracy: 0.001)
    }

    func testCanonicalYawAndPitchMapToSeparateCursorAxes() throws {
        var yawEngine = calibratedEngine()
        var pitchEngine = calibratedEngine()

        let yawDelta = try XCTUnwrap(yawEngine.process(
            sample: rawSample(bodyRate: Vector3(x: 0, y: 60, z: 0)),
            isActive: true,
            isPrecision: false,
            settings: PointerSettings()
        ))
        XCTAssertGreaterThan(abs(yawDelta.dx), 0)
        XCTAssertEqual(yawDelta.dy, 0, accuracy: 0.001)

        let pitchDelta = try XCTUnwrap(pitchEngine.process(
            sample: rawSample(bodyRate: Vector3(x: -60, y: 0, z: 0)),
            isActive: true,
            isPrecision: false,
            settings: PointerSettings()
        ))
        XCTAssertEqual(pitchDelta.dx, 0, accuracy: 0.001)
        XCTAssertGreaterThan(abs(pitchDelta.dy), 0)
    }

    func testHorizontalMotionIsIndependentOfControllerTilt() throws {
        var uprightEngine = calibratedEngine()
        let tiltedGravity = normalized(Vector3(x: 0, y: -1, z: -1))
        var tiltedEngine = calibratedEngine(gravity: tiltedGravity)

        let upright = try XCTUnwrap(uprightEngine.process(
            sample: rawSample(bodyRate: Vector3(x: 0, y: 60, z: 0)),
            isActive: true,
            isPrecision: false,
            settings: PointerSettings()
        ))
        let tilted = try XCTUnwrap(tiltedEngine.process(
            sample: rawSample(
                bodyRate: scaled(tiltedGravity, by: -60),
                gravity: tiltedGravity
            ),
            isActive: true,
            isPrecision: false,
            settings: PointerSettings()
        ))

        XCTAssertGreaterThan(tilted.dx * upright.dx, 0)
        XCTAssertGreaterThan(abs(tilted.dx / upright.dx), 0.6)
        XCTAssertLessThanOrEqual(abs(tilted.dx / upright.dx), 1)
        XCTAssertEqual(tilted.dy, 0, accuracy: 0.05)
    }

    func testVerticalMotionIsIndependentOfControllerTilt() throws {
        var uprightEngine = calibratedEngine()
        let tiltedGravity = normalized(Vector3(x: 0, y: -1, z: -1))
        var tiltedEngine = calibratedEngine(gravity: tiltedGravity)

        let upright = try XCTUnwrap(uprightEngine.process(
            sample: rawSample(bodyRate: Vector3(x: -60, y: 0, z: 0)),
            isActive: true,
            isPrecision: false,
            settings: PointerSettings()
        ))
        let tilted = try XCTUnwrap(tiltedEngine.process(
            sample: rawSample(
                bodyRate: Vector3(x: -60, y: 0, z: 0),
                gravity: tiltedGravity
            ),
            isActive: true,
            isPrecision: false,
            settings: PointerSettings()
        ))

        XCTAssertEqual(tilted.dx, 0, accuracy: 0.001)
        XCTAssertEqual(tilted.dy, upright.dy, accuracy: 0.001)
    }

    func testMeasuredButtonsUpGripWorldYawDoesNotLeakIntoVerticalMovement() throws {
        var engine = GyroPointerEngine()
        // Earlier hardware capture in the parser's raw report coordinates.
        let rawAcceleration = Vector3(x: 0.8, y: 0, z: -0.6)
        for _ in 0..<160 {
            _ = engine.process(
                sample: GyroSample(
                    degreesPerSecond: .zero,
                    acceleration: rawAcceleration
                ),
                isActive: false,
                isPrecision: false,
                settings: PointerSettings()
            )
        }

        // Correct remapping turns the captured support force into body
        // gravity (0, 0.6, 0.8), with no false local-pitch component.
        let capturedGravity = Vector3(x: 0, y: 0.6, z: 0.8)
        let delta = try XCTUnwrap(engine.process(
            sample: GyroSample(
                degreesPerSecond: rawGyro(fromBodyRate: scaled(capturedGravity, by: -60)),
                acceleration: rawAcceleration
            ),
            isActive: true,
            isPrecision: false,
            settings: PointerSettings()
        ))

        XCTAssertGreaterThan(abs(delta.dx), 1)
        XCTAssertEqual(delta.dy, 0, accuracy: 0.001)
    }

    func testWristRollIsIgnoredWhileControllerIsUpright() {
        var engine = calibratedEngine()
        let delta = engine.process(
            sample: rawSample(bodyRate: Vector3(x: 0, y: 0, z: 60)),
            isActive: true,
            isPrecision: false,
            settings: PointerSettings()
        )

        XCTAssertNil(delta)
    }

    func testDefaultGainMakesSmallTurnsUseful() throws {
        var engine = calibratedEngine()
        let delta = try XCTUnwrap(engine.process(
            sample: rawSample(bodyRate: Vector3(x: 0, y: 15, z: 0)),
            isActive: true,
            isPrecision: false,
            settings: PointerSettings()
        ))

        XCTAssertGreaterThan(abs(delta.dx), 0.6)
    }

    func testDefaultHorizontalGainIsHigherThanVerticalGain() throws {
        var horizontalEngine = calibratedEngine()
        var verticalEngine = calibratedEngine()

        let horizontal = try XCTUnwrap(horizontalEngine.process(
            sample: rawSample(bodyRate: Vector3(x: 0, y: 20, z: 0)),
            isActive: true,
            isPrecision: false,
            settings: PointerSettings()
        ))
        let vertical = try XCTUnwrap(verticalEngine.process(
            sample: rawSample(bodyRate: Vector3(x: -20, y: 0, z: 0)),
            isActive: true,
            isPrecision: false,
            settings: PointerSettings()
        ))

        XCTAssertEqual(abs(horizontal.dx / vertical.dy), 1.40, accuracy: 0.01)
    }

    func testFastTurnsReceiveMoreThanLinearPointerGain() throws {
        var moderateEngine = calibratedEngine()
        var fastEngine = calibratedEngine()

        let moderate = try XCTUnwrap(moderateEngine.process(
            sample: rawSample(bodyRate: Vector3(x: 0, y: 25, z: 0)),
            isActive: true,
            isPrecision: false,
            settings: PointerSettings()
        ))
        let fast = try XCTUnwrap(fastEngine.process(
            sample: rawSample(bodyRate: Vector3(x: 0, y: 80, z: 0)),
            isActive: true,
            isPrecision: false,
            settings: PointerSettings()
        ))

        XCTAssertGreaterThan(abs(fast.dx / moderate.dx), 4.5)
    }

    func testEstablishedAccelerationCurveSurvivesSensitivityRoundTrips() throws {
        var moderateEngine = calibratedEngine()
        var fastEngine = calibratedEngine()

        let moderate = try XCTUnwrap(moderateEngine.process(
            sample: rawSample(bodyRate: Vector3(x: 0, y: 25, z: 0)),
            isActive: true,
            isPrecision: false,
            settings: PointerSettings()
        ))
        let fast = try XCTUnwrap(fastEngine.process(
            sample: rawSample(bodyRate: Vector3(x: 0, y: 80, z: 0)),
            isActive: true,
            isPrecision: false,
            settings: PointerSettings()
        ))

        let linearSpeedRatio = 80.0 / 25.0
        let accelerationOnlyRatio = abs(fast.dx / moderate.dx) / linearSpeedRatio
        XCTAssertEqual(accelerationOnlyRatio, 1.7432, accuracy: 0.001)

        var uninterruptedEngine = calibratedEngine()
        var adjustedEngine = calibratedEngine()
        let sample = rawSample(bodyRate: Vector3(x: 0, y: 25, z: 0))
        for _ in 0..<8 {
            _ = uninterruptedEngine.process(
                sample: sample,
                isActive: true,
                isPrecision: false,
                settings: PointerSettings(sensitivity: 2.45)
            )
            _ = adjustedEngine.process(
                sample: sample,
                isActive: true,
                isPrecision: false,
                settings: PointerSettings(sensitivity: 1.25)
            )
        }
        let uninterrupted = try XCTUnwrap(uninterruptedEngine.process(
            sample: sample,
            isActive: true,
            isPrecision: false,
            settings: PointerSettings(sensitivity: 2.45)
        ))
        let restored = try XCTUnwrap(adjustedEngine.process(
            sample: sample,
            isActive: true,
            isPrecision: false,
            settings: PointerSettings(sensitivity: 2.45)
        ))
        XCTAssertEqual(restored, uninterrupted)
    }

    func testPointerAccelerationCanBeDisabled() throws {
        var moderateEngine = calibratedEngine()
        var fastEngine = calibratedEngine()
        let settings = PointerSettings(accelerationStrength: 0)

        let moderate = try XCTUnwrap(moderateEngine.process(
            sample: rawSample(bodyRate: Vector3(x: 0, y: 25, z: 0)),
            isActive: true,
            isPrecision: false,
            settings: settings
        ))
        let fast = try XCTUnwrap(fastEngine.process(
            sample: rawSample(bodyRate: Vector3(x: 0, y: 80, z: 0)),
            isActive: true,
            isPrecision: false,
            settings: settings
        ))

        XCTAssertEqual(abs(fast.dx / moderate.dx), 3.2, accuracy: 0.01)
    }

    func testPointerAccelerationDoesNotAmplifySlowAim() throws {
        var acceleratedEngine = calibratedEngine()
        var linearEngine = calibratedEngine()

        let accelerated = try XCTUnwrap(acceleratedEngine.process(
            sample: rawSample(bodyRate: Vector3(x: 0, y: 10, z: 0)),
            isActive: true,
            isPrecision: false,
            settings: PointerSettings(accelerationStrength: 2)
        ))
        let linear = try XCTUnwrap(linearEngine.process(
            sample: rawSample(bodyRate: Vector3(x: 0, y: 10, z: 0)),
            isActive: true,
            isPrecision: false,
            settings: PointerSettings(accelerationStrength: 0)
        ))

        XCTAssertEqual(accelerated.dx, linear.dx, accuracy: 0.001)
    }

    func testIntermittentLowSpeedNoiseIsAttenuatedOnEveryBurst() throws {
        var engine = calibratedEngine()

        for index in 0..<6 {
            XCTAssertNil(engine.process(
                sample: rawSample(bodyRate: .zero),
                isActive: true,
                isPrecision: false,
                settings: PointerSettings()
            ))

            let direction = index.isMultiple(of: 2) ? 1.0 : -1.0
            let jitter = engine.process(
                sample: rawSample(bodyRate: Vector3(x: 0, y: direction * 1.6, z: 0)),
                isActive: true,
                isPrecision: false,
                settings: PointerSettings()
            )
            XCTAssertLessThan(abs(jitter?.dx ?? 0), 0.12)
        }
    }

    func testSustainedHandTremorIsStronglySuppressedAfterSettling() {
        var engine = calibratedEngine()
        var finalDelta = 0.0

        for _ in 0..<120 {
            finalDelta = abs(engine.process(
                sample: rawSample(bodyRate: Vector3(x: 0, y: 1.0, z: 0)),
                isActive: true,
                isPrecision: false,
                settings: PointerSettings(accelerationStrength: 0)
            )?.dx ?? 0)
        }

        XCTAssertLessThan(finalDelta, 0.04)
    }

    func testDeliberateSmallMovementStillPassesStabilization() {
        var engine = calibratedEngine()
        var finalDelta = 0.0

        for _ in 0..<120 {
            finalDelta = abs(engine.process(
                sample: rawSample(bodyRate: Vector3(x: 0, y: 4.0, z: 0)),
                isActive: true,
                isPrecision: false,
                settings: PointerSettings(accelerationStrength: 0)
            )?.dx ?? 0)
        }

        XCTAssertGreaterThan(finalDelta, 0.70)
    }

    func testDeliberateSmallMovementRespondsWithinTwentyFiveMilliseconds() {
        var engine = calibratedEngine()
        var firstFiveDeltas: [Double] = []

        for _ in 0..<5 {
            firstFiveDeltas.append(abs(engine.process(
                sample: rawSample(bodyRate: Vector3(x: 0, y: 4.0, z: 0)),
                isActive: true,
                isPrecision: false,
                settings: PointerSettings(accelerationStrength: 0)
            )?.dx ?? 0))
        }

        XCTAssertGreaterThan(firstFiveDeltas.last ?? 0, 0.42)
    }

    func testStabilizationCanBeReducedForMaximumFineMovement() {
        var stabilizedEngine = calibratedEngine()
        var unrestrictedEngine = calibratedEngine()
        var stabilizedDelta = 0.0
        var unrestrictedDelta = 0.0

        for _ in 0..<120 {
            let sample = rawSample(bodyRate: Vector3(x: 0, y: 1.0, z: 0))
            stabilizedDelta = abs(stabilizedEngine.process(
                sample: sample,
                isActive: true,
                isPrecision: false,
                settings: PointerSettings(accelerationStrength: 0)
            )?.dx ?? 0)
            unrestrictedDelta = abs(unrestrictedEngine.process(
                sample: sample,
                isActive: true,
                isPrecision: false,
                settings: PointerSettings(
                    accelerationStrength: 0,
                    stabilizationStrength: 0
                )
            )?.dx ?? 0)
        }

        XCTAssertGreaterThan(unrestrictedDelta, stabilizedDelta * 3)
    }

    func testClutchReanchorsScreenAxesFromCurrentGravity() throws {
        var engine = calibratedEngine()
        let reclutchedGravity = normalized(Vector3(x: 0.6, y: -0.2, z: 0.77))
        let delta = try XCTUnwrap(engine.process(
            sample: rawSample(
                bodyRate: scaled(reclutchedGravity, by: 60),
                gravity: reclutchedGravity
            ),
            isActive: true,
            isPrecision: false,
            settings: PointerSettings()
        ))

        XCTAssertGreaterThan(abs(delta.dx), 0.5)
        XCTAssertEqual(delta.dy, 0, accuracy: 0.05)
    }

    func testHighSpeedClampPreservesCursorDirection() throws {
        var lowGainEngine = calibratedEngine()
        var highGainEngine = calibratedEngine()
        let sample = rawSample(bodyRate: Vector3(x: 30, y: -60, z: 0))

        let lowGain = try XCTUnwrap(lowGainEngine.process(
            sample: sample,
            isActive: true,
            isPrecision: false,
            settings: PointerSettings(sensitivity: 0.1, screenWidthPoints: 320)
        ))
        let highGain = try XCTUnwrap(highGainEngine.process(
            sample: sample,
            isActive: true,
            isPrecision: false,
            settings: PointerSettings(sensitivity: 100, screenWidthPoints: 5_000)
        ))

        XCTAssertEqual(hypot(highGain.dx, highGain.dy), 80, accuracy: 0.001)
        XCTAssertEqual(
            highGain.dy / highGain.dx,
            lowGain.dy / lowGain.dx,
            accuracy: 0.001
        )
    }

    func testCursorStopsWithoutFilterTail() throws {
        var engine = calibratedEngine()
        _ = try XCTUnwrap(engine.process(
            sample: rawSample(bodyRate: Vector3(x: 0, y: 60, z: 0)),
            isActive: true,
            isPrecision: false,
            settings: PointerSettings()
        ))

        XCTAssertNil(engine.process(
            sample: rawSample(bodyRate: .zero),
            isActive: true,
            isPrecision: false,
            settings: PointerSettings()
        ))
    }

    func testClutchCancelsRecentStationaryGyroBias() {
        var engine = calibratedEngine()
        let changedBias = Vector3(x: 0.7, y: -0.8, z: 0.4)

        // The controller rests on a table before the clutch is pressed, but its gyro
        // zero has shifted since startup calibration (for example, warm-up).
        for _ in 0..<80 {
            XCTAssertNil(engine.process(
                sample: rawSample(bodyRate: changedBias),
                isActive: false,
                isPrecision: false,
                settings: PointerSettings()
            ))
        }

        // Pressing the clutch must freeze that recent zero-rate observation;
        // a physically stationary controller must not walk the cursor.
        XCTAssertNil(engine.process(
            sample: rawSample(bodyRate: changedBias),
            isActive: true,
            isPrecision: false,
            settings: PointerSettings()
        ))
    }

    func testClutchDoesNotAbsorbInactiveMotionAboveStillnessThreshold() throws {
        var engine = calibratedEngine()
        let deliberateMotion = Vector3(x: 0, y: 8, z: 0)

        for _ in 0..<80 {
            _ = engine.process(
                sample: rawSample(bodyRate: deliberateMotion),
                isActive: false,
                isPrecision: false,
                settings: PointerSettings()
            )
        }

        let delta = try XCTUnwrap(engine.process(
            sample: rawSample(bodyRate: deliberateMotion),
            isActive: true,
            isPrecision: false,
            settings: PointerSettings()
        ))
        XCTAssertGreaterThan(abs(delta.dx), 0.1)
    }

    func testSensitivityScalesWithActiveScreenWidth() throws {
        var smallScreenEngine = calibratedEngine()
        var largeScreenEngine = calibratedEngine()
        let sample = rawSample(bodyRate: Vector3(x: 0, y: 60, z: 0))

        let small = try XCTUnwrap(smallScreenEngine.process(
            sample: sample,
            isActive: true,
            isPrecision: false,
            settings: PointerSettings(screenWidthPoints: 960)
        ))
        let large = try XCTUnwrap(largeScreenEngine.process(
            sample: sample,
            isActive: true,
            isPrecision: false,
            settings: PointerSettings(screenWidthPoints: 1920)
        ))

        XCTAssertEqual(large.dx / small.dx, 2, accuracy: 0.001)
    }

    func testMovementRestartsCalibrationWindow() {
        var engine = GyroPointerEngine()
        for _ in 0..<100 {
            _ = engine.process(
                sample: rawSample(bodyRate: .zero),
                isActive: false,
                isPrecision: false,
                settings: PointerSettings()
            )
        }

        _ = engine.process(
            sample: rawSample(bodyRate: Vector3(x: 20, y: 0, z: 0)),
            isActive: false,
            isPrecision: false,
            settings: PointerSettings()
        )
        XCTAssertEqual(engine.calibrationState, .calibrating(progress: 0))
    }

    private func calibratedEngine(
        gravity: Vector3 = GyroPointerEngineTests.defaultGravity
    ) -> GyroPointerEngine {
        var engine = GyroPointerEngine()
        for _ in 0..<160 {
            _ = engine.process(
                sample: rawSample(bodyRate: .zero, gravity: gravity),
                isActive: false,
                isPrecision: false,
                settings: PointerSettings()
            )
        }
        return engine
    }

    private static let defaultGravity = Vector3(x: 0, y: -1, z: 0)

    private func rawSample(
        bodyRate: Vector3,
        gravity: Vector3 = GyroPointerEngineTests.defaultGravity
    ) -> GyroSample {
        GyroSample(
            degreesPerSecond: rawGyro(fromBodyRate: bodyRate),
            acceleration: Vector3(
                x: gravity.z,
                y: gravity.x,
                z: -gravity.y
            )
        )
    }

    private func rawGyro(fromBodyRate rate: Vector3) -> Vector3 {
        Vector3(x: rate.z, y: -rate.x, z: rate.y)
    }

    private func normalized(_ vector: Vector3) -> Vector3 {
        scaled(vector, by: 1 / vector.magnitude)
    }

    private func scaled(_ vector: Vector3, by scalar: Double) -> Vector3 {
        Vector3(x: vector.x * scalar, y: vector.y * scalar, z: vector.z * scalar)
    }
}
