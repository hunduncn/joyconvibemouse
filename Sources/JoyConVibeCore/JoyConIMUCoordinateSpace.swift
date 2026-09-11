import Foundation

/// Converts Nintendo's right Joy-Con report axes into the controller body
/// frame used by the motion estimator.
///
/// Gyroscope and accelerometer reports do not share the same handedness. The
/// two transforms intentionally differ on body Z; merging them makes gravity
/// and angular velocity disagree as soon as the controller changes grip.
enum JoyConIMUCoordinateSpace {
    static func angularVelocity(from raw: Vector3) -> Vector3 {
        Vector3(x: -raw.y, y: raw.z, z: raw.x)
    }

    static func acceleration(from raw: Vector3) -> Vector3 {
        Vector3(x: -raw.y, y: raw.z, z: -raw.x)
    }
}
