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
        for i in steps.indices {
            if steps[i].name == name {
                steps[i].status = .inProgress
            } else if steps[i].status == .inProgress {
                steps[i].status = .completed
            }
        }
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
