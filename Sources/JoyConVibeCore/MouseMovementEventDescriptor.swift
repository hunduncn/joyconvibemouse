import Foundation

public struct MouseMovementEventDescriptor: Equatable, Sendable {
    public var destinationX: Double
    public var destinationY: Double
    public var relativeDeltaX: Int64
    public var relativeDeltaY: Int64

    public init(currentX: Double, currentY: Double, delta: PointerDelta) {
        destinationX = currentX + delta.dx
        destinationY = currentY + delta.dy
        relativeDeltaX = Int64(delta.dx.rounded(.toNearestOrAwayFromZero))
        relativeDeltaY = Int64(delta.dy.rounded(.toNearestOrAwayFromZero))
    }
}
