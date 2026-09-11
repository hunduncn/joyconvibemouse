import Foundation

public struct ScheduledPointerDelta: Equatable, Sendable {
    public var delay: TimeInterval
    public var delta: PointerDelta

    public init(delay: TimeInterval, delta: PointerDelta) {
        self.delay = delay
        self.delta = delta
    }
}

public enum PointerMotionPacingPlan {
    /// A standard Joy-Con input report batches three IMU samples measured at
    /// 200 Hz. Pacing them at their physical 5 ms interval avoids posting a
    /// burst of three cursor jumps followed by a visible gap.
    public static func steps(
        for deltas: [PointerDelta],
        sampleInterval: TimeInterval = 1.0 / 200.0
    ) -> [ScheduledPointerDelta] {
        deltas.enumerated().map { index, delta in
            ScheduledPointerDelta(
                delay: Double(index) * sampleInterval,
                delta: delta
            )
        }
    }
}
