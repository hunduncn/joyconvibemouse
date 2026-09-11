import Foundation
import JoyConVibeCore

@MainActor
final class PointerMotionEmitter {
    private let eventEmitter: SystemEventEmitter
    private var generation: UInt = 0

    init(eventEmitter: SystemEventEmitter) {
        self.eventEmitter = eventEmitter
    }

    func emit(_ deltas: [PointerDelta]) {
        let currentGeneration = generation
        for step in PointerMotionPacingPlan.steps(for: deltas) {
            if step.delay == 0 {
                eventEmitter.moveCursor(by: step.delta)
                continue
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + step.delay) { [weak self] in
                guard let self, self.generation == currentGeneration else { return }
                self.eventEmitter.moveCursor(by: step.delta)
            }
        }
    }

    func reset() {
        generation &+= 1
    }
}
