import SwiftUI

enum SwarmStepStatus: String {
    case pending
    case inProgress
    case completed
}

struct SwarmStep: Identifiable {
    let id: UUID
    let name: String
    var status: SwarmStepStatus

    init(id: UUID = UUID(), name: String, status: SwarmStepStatus = .pending) {
        self.id = id
        self.name = name
        self.status = status
    }
}

@MainActor
final class SwarmProgressStore: ObservableObject {
    @Published var steps: [SwarmStep] = []

    func setSteps(_ names: [String]) {
        let existingByName = Dictionary(uniqueKeysWithValues: steps.map { ($0.name, $0.status) })
        // Build new array then assign once (single @Published notification)
        let newSteps = names.map { name in
            let preserved = existingByName[name]
            let status: SwarmStepStatus = (preserved == .completed || preserved == .inProgress) ? preserved! : .pending
            return SwarmStep(name: name, status: status)
        }
        steps = newSteps
    }

    func markStarted(name: String) {
        guard let targetIndex = steps.firstIndex(where: { $0.name == name }) else { return }
        // Mutate a local copy, assign once to trigger a single @Published update
        var updated = steps
        // Only auto-complete the immediate predecessor when it is in progress.
        // This keeps linear flows tidy without forcing unrelated parallel steps to complete.
        if targetIndex > 0 {
            let predecessor = targetIndex - 1
            if updated[predecessor].status == .inProgress {
                updated[predecessor].status = .completed
            }
        }
        if updated[targetIndex].status != .completed {
            updated[targetIndex].status = .inProgress
        }
        steps = updated
    }

    func markCompleted(name: String) {
        guard let idx = steps.firstIndex(where: { $0.name == name }) else { return }
        var updated = steps
        updated[idx].status = .completed
        steps = updated
    }

    func clear() {
        steps.removeAll()
    }
}
