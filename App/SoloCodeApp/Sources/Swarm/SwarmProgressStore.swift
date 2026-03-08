import Foundation
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
    @Published private var stepsByConversation: [String: [SwarmStep]] = [:]

    func steps(for conversationId: UUID?) -> [SwarmStep] {
        guard let scope = normalizedConversationScope(conversationId) else { return steps }
        return stepsByConversation[scope] ?? []
    }

    func setSteps(_ names: [String], conversationId: UUID? = nil) {
        if let scope = normalizedConversationScope(conversationId) {
            let existing = stepsByConversation[scope] ?? []
            let existingByName = Dictionary(existing.map { ($0.name, $0.status) }, uniquingKeysWith: { first, _ in first })
            let newSteps = names.map { name in
                let preserved = existingByName[name]
                let status: SwarmStepStatus = preserved ?? .pending
                return SwarmStep(name: name, status: status)
            }
            stepsByConversation[scope] = newSteps
            return
        }

        let existingByName = Dictionary(steps.map { ($0.name, $0.status) }, uniquingKeysWith: { first, _ in first })
        // Build new array then assign once (single @Published notification)
        let newSteps = names.map { name in
            let preserved = existingByName[name]
            let status: SwarmStepStatus = preserved ?? .pending
            return SwarmStep(name: name, status: status)
        }
        steps = newSteps
    }

    func markStarted(name: String, conversationId: UUID? = nil) {
        if let scope = normalizedConversationScope(conversationId) {
            guard let targetIndex = stepsByConversation[scope]?.firstIndex(where: { $0.name == name }) else { return }
            var updated = stepsByConversation[scope] ?? []
            if targetIndex > 0 {
                let predecessor = targetIndex - 1
                if updated[predecessor].status == .inProgress {
                    updated[predecessor].status = .completed
                }
            }
            if updated[targetIndex].status != .completed {
                updated[targetIndex].status = .inProgress
            }
            stepsByConversation[scope] = updated
            return
        }

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

    func markCompleted(name: String, conversationId: UUID? = nil) {
        if let scope = normalizedConversationScope(conversationId) {
            guard let idx = stepsByConversation[scope]?.firstIndex(where: { $0.name == name }) else { return }
            var updated = stepsByConversation[scope] ?? []
            updated[idx].status = .completed
            stepsByConversation[scope] = updated
            return
        }

        guard let idx = steps.firstIndex(where: { $0.name == name }) else { return }
        var updated = steps
        updated[idx].status = .completed
        steps = updated
    }

    func clear(conversationId: UUID? = nil) {
        if let scope = normalizedConversationScope(conversationId) {
            stepsByConversation.removeValue(forKey: scope)
            return
        }

        steps.removeAll()
        stepsByConversation.removeAll()
    }

    private func normalizedConversationScope(_ conversationId: UUID?) -> String? {
        guard let conversationId else { return nil }
        return conversationId.uuidString.lowercased()
    }
}
