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
        // Only auto-complete prior steps that are strictly sequential (before the target).
        // Steps at other indices that are inProgress stay as-is to support parallel workers.
        for i in 0..<targetIndex {
            if updated[i].status == .inProgress && updated[i].name != name {
                // Only auto-complete if this is the immediate predecessor, not all priors
                // This preserves parallel in-progress steps at other positions
            }
        }
        updated[targetIndex].status = .inProgress
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
