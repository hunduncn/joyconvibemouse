import Foundation

public enum GyroCalibrationState: Equatable, Sendable {
    case calibrating(progress: Double)
    case ready
}

public struct GyroPointerEngine: Sendable {
    private let targetCalibrationSamples = 160
    private var calibrationSum = Vector3.zero
    private var calibrationCount = 0
    private var runtimeBias = Vector3.zero
    private var gravityEstimator = FusedGravityEstimator()
    private var filteredHorizontalRate = 0.0
    private var filteredVerticalRate = 0.0
    private var isSmoothingLowSpeed = false
    private var rayOrientation = RelativeOrientation.identity
    private var anchorRight: Vector3?
    private var anchorUp: Vector3?
    private var previousRayAngles = (horizontal: 0.0, vertical: 0.0)
    private var wasActive = false
    private var idleBiasEstimate = Vector3.zero
    private var idleBiasSampleCount = 0
    private var previousIdleAccelerationDirection: Vector3?

    public private(set) var calibrationState: GyroCalibrationState = .calibrating(progress: 0)

    public init() {}

    public mutating func beginCalibration() {
        calibrationSum = .zero
        calibrationCount = 0
        runtimeBias = .zero
        gravityEstimator.reset()
        clearIdleBiasCandidate()
        resetMotion()
        calibrationState = .calibrating(progress: 0)
    }

    public mutating func resetMotion() {
        filteredHorizontalRate = 0
        filteredVerticalRate = 0
        isSmoothingLowSpeed = false
        rayOrientation = .identity
        anchorRight = nil
        anchorUp = nil
        previousRayAngles = (0, 0)
        wasActive = false
    }

    public mutating func process(
        sample: GyroSample,
        isActive: Bool,
        isPrecision: Bool,
        settings: PointerSettings
    ) -> PointerDelta? {
        let raw = sample.degreesPerSecond
        let canonicalAcceleration = JoyConIMUCoordinateSpace.acceleration(
            from: sample.acceleration
        )

        if case .calibrating = calibrationState {
            _ = gravityEstimator.update(
                angularVelocity: JoyConIMUCoordinateSpace.angularVelocity(from: raw),
                acceleration: canonicalAcceleration
            )
            collectCalibrationSample(raw)
            return nil
        }

        let justActivated = isActive && !wasActive
        if justActivated {
            applyRecentIdleBiasIfReady()
            // The clutch is a recenter boundary. Start a fresh screen tangent
            // and remove every 2D filter tail, while keeping the continuously
            // fused gravity estimate intact.
            resetMotion()
        }

        let adjusted = Vector3(
            x: raw.x - runtimeBias.x,
            y: raw.y - runtimeBias.y,
            z: raw.z - runtimeBias.z
        )
        let canonicalRate = JoyConIMUCoordinateSpace.angularVelocity(from: adjusted)
        let gravity = gravityEstimator.update(
            angularVelocity: canonicalRate,
            acceleration: canonicalAcceleration
        )

        guard isActive else {
            collectIdleBiasCandidate(
                rawAngularVelocity: raw,
                canonicalAcceleration: canonicalAcceleration
            )
            resetMotion()
            return nil
        }
        wasActive = true

        // The clutch anchors the controller's current pose to the current cursor. A
        // complete relative orientation rotates the Joy-Con's face normal as
        // a virtual ray, so compound wrist motion is resolved by where the
        // controller points rather than by projecting each instantaneous gyro
        // sample independently. Pure roll around that ray does not move it.
        let clutchGravity: Vector3
        if justActivated, canonicalAcceleration.magnitude > 0.001 {
            // The clutch is also an orientation recenter boundary. The fused estimate
            // may still reflect a fast inactive re-grip, while the current
            // accelerometer gives the only observable screen-up reference.
            clutchGravity = scaled(
                canonicalAcceleration,
                by: -1 / canonicalAcceleration.magnitude
            )
        } else {
            clutchGravity = gravity
        }
        var (horizontalRate, verticalRate) = updateAnchoredRay(
            gravity: clutchGravity,
            angularVelocity: canonicalRate
        )
        (horizontalRate, verticalRate) = applyCardinalStabilization(
            horizontal: horizontalRate,
            vertical: verticalRate
        )
        (horizontalRate, verticalRate) = applyRadialSoftCutoff(
            horizontal: horizontalRate,
            vertical: verticalRate,
            strength: settings.stabilizationStrength
        )
        (horizontalRate, verticalRate) = applyLowSpeedSmoothing(
            horizontal: horizontalRate,
            vertical: verticalRate
        )

        let accelerationGain = pointerAccelerationGain(
            // Use the controller's physical angular speed so the same hand
            // motion receives the same acceleration in upright and tilted
            // grips. The mapped ray speed varies with projection geometry.
            speed: canonicalRate.magnitude,
            strength: settings.accelerationStrength
        )
        horizontalRate *= accelerationGain
        verticalRate *= accelerationGain
        horizontalRate *= max(0.1, settings.horizontalSensitivityMultiplier)
        if settings.invertHorizontal { horizontalRate *= -1 }
        if settings.invertVertical { verticalRate *= -1 }

        let precision = isPrecision ? settings.precisionMultiplier : 1
        let degreesForFullWidth = 45.0
        let pixelsPerDegree = max(320, settings.screenWidthPoints)
            / degreesForFullWidth
            * max(0.1, settings.sensitivity)
            * precision
        let sampleInterval = 1.0 / 200.0
        var dx = horizontalRate * pixelsPerDegree * sampleInterval
        var dy = verticalRate * pixelsPerDegree * sampleInterval
        let deltaMagnitude = hypot(dx, dy)
        let maximumDeltaPerSample = 80.0
        if deltaMagnitude > maximumDeltaPerSample {
            let scale = maximumDeltaPerSample / deltaMagnitude
            dx *= scale
            dy *= scale
        }

        guard abs(dx) >= 0.02 || abs(dy) >= 0.02 else { return nil }
        return PointerDelta(dx: dx, dy: dy)
    }

    private func dot(_ lhs: Vector3, _ rhs: Vector3) -> Double {
        lhs.x * rhs.x + lhs.y * rhs.y + lhs.z * rhs.z
    }

    private mutating func updateAnchoredRay(
        gravity: Vector3,
        angularVelocity: Vector3
    ) -> (Double, Double) {
        let forward = Vector3(x: 0, y: 0, z: 1)
        if anchorRight == nil || anchorUp == nil {
            let gravityRight = cross(forward, gravity)
            // Pointing the Joy-Con face exactly along gravity has no physical
            // screen-right reference. Use its local right axis only for that
            // degenerate pose; every ordinary grip uses gravity compensation.
            let right = gravityRight.magnitude > 0.12
                ? normalized(gravityRight)
                : Vector3(x: 1, y: 0, z: 0)
            anchorRight = right
            anchorUp = normalized(cross(right, forward))
            rayOrientation = .identity
            previousRayAngles = (0, 0)
        }

        rayOrientation.integrate(
            angularVelocityDegreesPerSecond: angularVelocity,
            sampleInterval: 1.0 / 200.0
        )
        guard let anchorRight, let anchorUp else { return (0, 0) }
        let ray = normalized(rayOrientation.rotated(forward))
        let horizontalAngle = atan2(dot(ray, anchorRight), dot(ray, forward))
        let verticalAngle = atan2(
            dot(ray, anchorUp),
            hypot(dot(ray, anchorRight), dot(ray, forward))
        )
        let horizontalDelta = wrappedAngle(horizontalAngle - previousRayAngles.horizontal)
        let verticalDelta = wrappedAngle(verticalAngle - previousRayAngles.vertical)
        previousRayAngles = (horizontalAngle, verticalAngle)

        let radiansToDegreesPerSecond = 180 / Double.pi * 200
        return (
            horizontalDelta * radiansToDegreesPerSecond,
            verticalDelta * radiansToDegreesPerSecond
        )
    }

    private func applyCardinalStabilization(
        horizontal: Double,
        vertical: Double
    ) -> (Double, Double) {
        let horizontalMagnitude = abs(horizontal)
        let verticalMagnitude = abs(vertical)
        let major = max(horizontalMagnitude, verticalMagnitude)
        let minor = min(horizontalMagnitude, verticalMagnitude)
        guard major > 0.0001 else { return (0, 0) }

        // Fully suppress tiny cross-axis motion, then hand back smoothly to
        // unmodified input as it approaches a deliberate diagonal.
        let ratio = minor / major
        let zeroLeakageRatio = 0.25
        let fullDiagonalRatio = 0.80
        let progress = min(
            1,
            max(0, (ratio - zeroLeakageRatio) / (fullDiagonalRatio - zeroLeakageRatio))
        )
        let minorScale = progress * progress * (3 - 2 * progress)
        if horizontalMagnitude >= verticalMagnitude {
            return (horizontal, vertical * minorScale)
        }
        return (horizontal * minorScale, vertical)
    }

    private func cross(_ lhs: Vector3, _ rhs: Vector3) -> Vector3 {
        Vector3(
            x: lhs.y * rhs.z - lhs.z * rhs.y,
            y: lhs.z * rhs.x - lhs.x * rhs.z,
            z: lhs.x * rhs.y - lhs.y * rhs.x
        )
    }

    private func wrappedAngle(_ angle: Double) -> Double {
        var result = angle
        while result > .pi { result -= 2 * .pi }
        while result < -.pi { result += 2 * .pi }
        return result
    }

    private func normalized(_ vector: Vector3) -> Vector3 {
        let magnitude = vector.magnitude
        return magnitude > 0.001 ? scaled(vector, by: 1 / magnitude) : .zero
    }

    private func scaled(_ vector: Vector3, by scalar: Double) -> Vector3 {
        Vector3(x: vector.x * scalar, y: vector.y * scalar, z: vector.z * scalar)
    }

    private mutating func collectIdleBiasCandidate(
        rawAngularVelocity: Vector3,
        canonicalAcceleration: Vector3
    ) {
        let residual = Vector3(
            x: rawAngularVelocity.x - runtimeBias.x,
            y: rawAngularVelocity.y - runtimeBias.y,
            z: rawAngularVelocity.z - runtimeBias.z
        )
        let accelerationMagnitude = canonicalAcceleration.magnitude
        guard residual.magnitude < 3, accelerationMagnitude > 0.001 else {
            clearIdleBiasCandidate()
            return
        }

        let accelerationDirection = scaled(
            canonicalAcceleration,
            by: 1 / accelerationMagnitude
        )
        if let previous = previousIdleAccelerationDirection {
            let directionChange = Vector3(
                x: accelerationDirection.x - previous.x,
                y: accelerationDirection.y - previous.y,
                z: accelerationDirection.z - previous.z
            )
            guard directionChange.magnitude < 0.02 else {
                clearIdleBiasCandidate()
                previousIdleAccelerationDirection = accelerationDirection
                return
            }
        }
        previousIdleAccelerationDirection = accelerationDirection

        let nextCount = min(idleBiasSampleCount + 1, 160)
        let alpha = 1 / Double(nextCount)
        idleBiasEstimate.x += alpha * (rawAngularVelocity.x - idleBiasEstimate.x)
        idleBiasEstimate.y += alpha * (rawAngularVelocity.y - idleBiasEstimate.y)
        idleBiasEstimate.z += alpha * (rawAngularVelocity.z - idleBiasEstimate.z)
        idleBiasSampleCount = nextCount
        if idleBiasSampleCount >= 60 {
            // Keep the continuously running gravity estimator on the same
            // freshly measured zero while the controller remains inactive.
            runtimeBias = idleBiasEstimate
        }
    }

    private mutating func applyRecentIdleBiasIfReady() {
        // 60 Joy-Con subsamples are roughly 300 ms: long enough to reject a
        // button-handling transient, short enough to recenter naturally each
        // time the user pauses before pressing the clutch.
        if idleBiasSampleCount >= 60 {
            runtimeBias = idleBiasEstimate
        }
        clearIdleBiasCandidate()
    }

    private mutating func clearIdleBiasCandidate() {
        idleBiasEstimate = .zero
        idleBiasSampleCount = 0
        previousIdleAccelerationDirection = nil
    }

    private func applyRadialSoftCutoff(
        horizontal: Double,
        vertical: Double,
        strength: Double
    ) -> (Double, Double) {
        let speed = hypot(horizontal, vertical)
        let clampedStrength = min(2, max(0, strength))
        let cutoff = 0.20 + 0.35 * clampedStrength
        let recovery = 1.25 + 1.75 * clampedStrength
        guard speed > cutoff else { return (0, 0) }
        guard speed < recovery else { return (horizontal, vertical) }
        let progress = (speed - cutoff) / (recovery - cutoff)
        let scale = progress * progress * (3 - 2 * progress)
        return (horizontal * scale, vertical * scale)
    }

    private mutating func applyLowSpeedSmoothing(
        horizontal: Double,
        vertical: Double
    ) -> (Double, Double) {
        let speed = hypot(horizontal, vertical)
        let threshold = 18.0
        if speed <= 0.0001 {
            filteredHorizontalRate = 0
            filteredVerticalRate = 0
            isSmoothingLowSpeed = false
            return (0, 0)
        }
        if speed >= threshold {
            filteredHorizontalRate = horizontal
            filteredVerticalRate = vertical
            isSmoothingLowSpeed = false
            return (horizontal, vertical)
        }

        if !isSmoothingLowSpeed {
            // Starting from zero prevents an isolated gyro-noise sample from
            // bypassing the filter every time the input returns to rest.
            filteredHorizontalRate = 0
            filteredVerticalRate = 0
            isSmoothingLowSpeed = true
        }

        // Keep isolated tremor attenuation while letting a deliberate
        // low-speed gesture become responsive within about 25 ms.
        let fullSmoothingAlpha = 1 - pow(0.5, (1.0 / 200.0) / 0.025)
        let transitionStart = threshold * 0.20
        let transition = min(
            1,
            max(0, (speed - transitionStart) / (threshold - transitionStart))
        )
        let smoothTransition = transition * transition * (3 - 2 * transition)
        let alpha = fullSmoothingAlpha + (1 - fullSmoothingAlpha) * smoothTransition
        filteredHorizontalRate += alpha * (horizontal - filteredHorizontalRate)
        filteredVerticalRate += alpha * (vertical - filteredVerticalRate)
        return (filteredHorizontalRate, filteredVerticalRate)
    }

    private func pointerAccelerationGain(
        speed: Double,
        strength: Double
    ) -> Double {
        let startSpeed = 12.0
        let fullSpeed = 90.0
        guard speed > startSpeed else { return 1 }

        let progress = min(1, (speed - startSpeed) / (fullSpeed - startSpeed))
        let smoothProgress = progress * progress * (3 - 2 * progress)
        let clampedStrength = min(2, max(0, strength))
        return 1 + 0.90 * clampedStrength * smoothProgress
    }

    private mutating func collectCalibrationSample(_ sample: Vector3) {
        // Moving the controller restarts the stationary calibration window.
        if sample.magnitude > 8 {
            calibrationSum = .zero
            calibrationCount = 0
            calibrationState = .calibrating(progress: 0)
            return
        }

        calibrationSum.x += sample.x
        calibrationSum.y += sample.y
        calibrationSum.z += sample.z
        calibrationCount += 1

        if calibrationCount >= targetCalibrationSamples {
            let count = Double(calibrationCount)
            runtimeBias = Vector3(
                x: calibrationSum.x / count,
                y: calibrationSum.y / count,
                z: calibrationSum.z / count
            )
            calibrationState = .ready
        } else {
            calibrationState = .calibrating(
                progress: Double(calibrationCount) / Double(targetCalibrationSamples)
            )
        }
    }

}

private struct RelativeOrientation: Sendable {
    var w: Double
    var x: Double
    var y: Double
    var z: Double

    static let identity = RelativeOrientation(w: 1, x: 0, y: 0, z: 0)

    mutating func integrate(
        angularVelocityDegreesPerSecond velocity: Vector3,
        sampleInterval: Double
    ) {
        let speedDegrees = velocity.magnitude
        guard speedDegrees > 0.0001 else { return }
        let axisScale = 1 / speedDegrees
        let halfAngle = speedDegrees * .pi / 180 * sampleInterval / 2
        let sine = sin(halfAngle)
        let delta = RelativeOrientation(
            w: cos(halfAngle),
            x: velocity.x * axisScale * sine,
            y: velocity.y * axisScale * sine,
            z: velocity.z * axisScale * sine
        )
        self = multiplied(by: delta).normalized()
    }

    func rotated(_ vector: Vector3) -> Vector3 {
        let imaginary = Vector3(x: x, y: y, z: z)
        let doubledCross = scaled(cross(imaginary, vector), by: 2)
        return added(
            vector,
            added(
                scaled(doubledCross, by: w),
                cross(imaginary, doubledCross)
            )
        )
    }

    private func multiplied(by rhs: RelativeOrientation) -> RelativeOrientation {
        RelativeOrientation(
            w: w * rhs.w - x * rhs.x - y * rhs.y - z * rhs.z,
            x: w * rhs.x + x * rhs.w + y * rhs.z - z * rhs.y,
            y: w * rhs.y - x * rhs.z + y * rhs.w + z * rhs.x,
            z: w * rhs.z + x * rhs.y - y * rhs.x + z * rhs.w
        )
    }

    private func normalized() -> RelativeOrientation {
        let magnitude = sqrt(w * w + x * x + y * y + z * z)
        guard magnitude > 0.0001 else { return .identity }
        return RelativeOrientation(
            w: w / magnitude,
            x: x / magnitude,
            y: y / magnitude,
            z: z / magnitude
        )
    }

    private func cross(_ lhs: Vector3, _ rhs: Vector3) -> Vector3 {
        Vector3(
            x: lhs.y * rhs.z - lhs.z * rhs.y,
            y: lhs.z * rhs.x - lhs.x * rhs.z,
            z: lhs.x * rhs.y - lhs.y * rhs.x
        )
    }

    private func scaled(_ vector: Vector3, by scalar: Double) -> Vector3 {
        Vector3(x: vector.x * scalar, y: vector.y * scalar, z: vector.z * scalar)
    }

    private func added(_ lhs: Vector3, _ rhs: Vector3) -> Vector3 {
        Vector3(x: lhs.x + rhs.x, y: lhs.y + rhs.y, z: lhs.z + rhs.z)
    }
}
