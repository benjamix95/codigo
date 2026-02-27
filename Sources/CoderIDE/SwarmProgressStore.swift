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
        steps = names.map { SwarmStep(name: $0, status: .pending) }
    }

    func markStarted(name: String) {
        guard let targetIndex = steps.firstIndex(where: { $0.name == name }) else { return }
        // Only auto-complete steps that come BEFORE the target in sequential order.
        // Steps after the target that are somehow inProgress should not be touched.
        for i in 0..<targetIndex {
            if steps[i].status == .inProgress {
                steps[i].status = .completed
            }
        }
        steps[targetIndex].status = .inProgress
    }

    func markCompleted(name: String) {
        if let idx = steps.firstIndex(where: { $0.name == name }) {
            steps[idx].status = .completed
        }
    }

    func clear() {
        steps.removeAll()
    }
}
