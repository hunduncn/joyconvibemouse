import Foundation

/// Six-axis gravity tracking adapted from the approach used by
/// GamepadMotionHelpers: gyro propagation supplies responsive motion while a
/// shakiness-aware accelerometer correction removes long-term tilt drift.
struct FusedGravityEstimator: Sendable {
    private let sampleInterval = 1.0 / 200.0
    private var gravity = Vector3.zero
    private var smoothAcceleration = Vector3.zero
    private var shakiness = 0.0
    private var hasEstimate = false

    mutating func reset() {
        gravity = .zero
        smoothAcceleration = .zero
        shakiness = 0
        hasEstimate = false
    }

    mutating func update(
        angularVelocity: Vector3,
        acceleration: Vector3
    ) -> Vector3 {
        if hasEstimate {
            gravity = rotatedByInverseGyro(gravity, angularVelocity: angularVelocity)
            smoothAcceleration = rotatedByInverseGyro(
                smoothAcceleration,
                angularVelocity: angularVelocity
            )
        }

        let accelerationMagnitude = acceleration.magnitude
        guard accelerationMagnitude > 0.001 else {
            return hasEstimate ? normalized(gravity) : Vector3(x: 0, y: -1, z: 0)
        }

        // An accelerometer reports support force, which points opposite the
        // gravity vector used by GamepadMotionHelpers' world-space mapping.
        // Joy-Con report polarity is fixed; it must never be guessed from the
        // first grip's dominant component.
        let measuredGravity = scaled(acceleration, by: -1 / accelerationMagnitude)
        if !hasEstimate {
            gravity = measuredGravity
            smoothAcceleration = measuredGravity
            hasEstimate = true
            return gravity
        }

        let smoothFactor = pow(0.5, sampleInterval / 0.25)
        shakiness *= smoothFactor
        shakiness = max(shakiness, subtracted(measuredGravity, smoothAcceleration).magnitude)
        smoothAcceleration = added(
            scaled(measuredGravity, by: 1 - smoothFactor),
            scaled(smoothAcceleration, by: smoothFactor)
        )

        let shakinessAmount = clamp((shakiness - 0.01) / (0.40 - 0.01))
        var correctionSpeed = 1.0 + (0.1 - 1.0) * shakinessAmount
        let angularSpeed = angularVelocity.magnitude * .pi / 180
        let gyroCorrectionLimit = max(angularSpeed * 0.1, 0.01)
        let difference = subtracted(measuredGravity, gravity)
        let differenceMagnitude = difference.magnitude

        if correctionSpeed > gyroCorrectionLimit {
            let closeEnough = clamp((differenceMagnitude - 0.05) / (0.25 - 0.05))
            correctionSpeed = gyroCorrectionLimit
                + (correctionSpeed - gyroCorrectionLimit) * closeEnough
        }

        let correctionDistance = correctionSpeed * sampleInterval
        if differenceMagnitude > correctionDistance, differenceMagnitude > 0.001 {
            gravity = added(
                gravity,
                scaled(difference, by: correctionDistance / differenceMagnitude)
            )
        } else {
            gravity = measuredGravity
        }
        gravity = normalized(gravity)
        return gravity
    }

    private func rotatedByInverseGyro(
        _ vector: Vector3,
        angularVelocity: Vector3
    ) -> Vector3 {
        let speed = angularVelocity.magnitude
        guard speed > 0.0001 else { return vector }

        let axis = scaled(angularVelocity, by: 1 / speed)
        let angle = -speed * .pi / 180 * sampleInterval
        let cosine = cos(angle)
        let sine = sin(angle)
        let axisProjection = dot(axis, vector) * (1 - cosine)
        let cross = Vector3(
            x: axis.y * vector.z - axis.z * vector.y,
            y: axis.z * vector.x - axis.x * vector.z,
            z: axis.x * vector.y - axis.y * vector.x
        )
        return Vector3(
            x: vector.x * cosine + cross.x * sine + axis.x * axisProjection,
            y: vector.y * cosine + cross.y * sine + axis.y * axisProjection,
            z: vector.z * cosine + cross.z * sine + axis.z * axisProjection
        )
    }

    private func normalized(_ vector: Vector3) -> Vector3 {
        let magnitude = vector.magnitude
        return magnitude > 0.001 ? scaled(vector, by: 1 / magnitude) : .zero
    }

    private func dot(_ lhs: Vector3, _ rhs: Vector3) -> Double {
        lhs.x * rhs.x + lhs.y * rhs.y + lhs.z * rhs.z
    }

    private func scaled(_ vector: Vector3, by scalar: Double) -> Vector3 {
        Vector3(x: vector.x * scalar, y: vector.y * scalar, z: vector.z * scalar)
    }

    private func added(_ lhs: Vector3, _ rhs: Vector3) -> Vector3 {
        Vector3(x: lhs.x + rhs.x, y: lhs.y + rhs.y, z: lhs.z + rhs.z)
    }

    private func subtracted(_ lhs: Vector3, _ rhs: Vector3) -> Vector3 {
        Vector3(x: lhs.x - rhs.x, y: lhs.y - rhs.y, z: lhs.z - rhs.z)
    }

    private func clamp(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}
