import Foundation

/// Frame-level seam between IMU decoding and cursor emission.
///
/// Joy-Con reports contain three historical IMU subsamples but only one
/// current clutch-button state, so clutch transitions must be resolved at report
/// boundaries rather than independently for each subsample.
public struct ClutchedPointerFrameBuffer: Sendable {
    private var pendingDeltas: [PointerDelta] = []
    private var wasActive = false

    public init() {}

    public mutating func process(
        frameDeltas: [PointerDelta],
        isActive: Bool
    ) -> [PointerDelta] {
        guard isActive else {
            pendingDeltas.removeAll(keepingCapacity: true)
            wasActive = false
            return []
        }

        guard wasActive else {
            // The report that first observes the clutch as pressed also carries
            // three historical IMU samples from the physical button press.
            // They must establish the new clutch boundary, never move the
            // pointer on the following report.
            wasActive = true
            pendingDeltas.removeAll(keepingCapacity: true)
            return []
        }

        let confirmedDeltas = pendingDeltas
        pendingDeltas = frameDeltas
        return confirmedDeltas
    }

    public mutating func reset() {
        pendingDeltas.removeAll(keepingCapacity: true)
        wasActive = false
    }
}
