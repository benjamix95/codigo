import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    @MainActor
    func resolvePlanMutationConversationId(
        rawConversationId: String?,
        fallbackConversationId: UUID?
    ) -> UUID? {
        if let rawConversationId = rawConversationId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rawConversationId.isEmpty,
           let parsed = UUID(uuidString: rawConversationId) {
            return parsed
        }
        return resolvePlanStepTargetConversationId(
            eventConversationId: fallbackConversationId,
            activeBuildPlanConversationId: activeBuildPlanConversationId,
            activeTaskConversationId: chatStore.activeTaskConversationId
        )
    }

    @MainActor
    func inferredPlanStepTitle(
        candidate: String?,
        stepId: String,
        conversationId: UUID?
    ) -> String? {
        let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            return trimmed
        }
        return chatStore.planBoard(for: conversationId)?
            .steps
            .first(where: { $0.id == stepId })?
            .title
    }

    @MainActor
    func syncCanonicalTodoFromPlanStep(
        title: String?,
        status: PlanStepStatus,
        targetConversationId: UUID?
    ) {
        guard let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty else {
            return
        }
        let todoStatus: TodoStatus = {
            switch status {
            case .pending: return .pending
            case .running: return .inProgress
            case .done: return .done
            case .failed: return .blocked
            }
        }()
        let stepActiveForm: String? = status == .running ? title : nil
        let isBuildScoped = isPlanBuildContext(
            conversationId: targetConversationId,
            phase: planFlowPhase,
            activeBuildPlanConversationId: activeBuildPlanConversationId,
            activeBuildAgentConversationId: activeBuildAgentConversationId
        )
        let canonicalConversationId = resolveCanonicalPlanTodoConversationId(
            targetConversationId: targetConversationId,
            phase: planFlowPhase,
            activeBuildPlanConversationId: activeBuildPlanConversationId,
            activeBuildAgentConversationId: activeBuildAgentConversationId
        )
        let updated = todoStore.upsertCanonicalOnlyFromAgent(
            id: nil,
            title: title,
            status: todoStatus,
            priority: nil,
            notes: nil,
            activeForm: stepActiveForm,
            linkedFiles: [],
            conversationId: canonicalConversationId
        )
        if updated {
            if todoStatus == .done {
                _ = todoStore.advanceNextCanonicalTodoIfNeeded(conversationId: canonicalConversationId)
            }
            if let syncId = canonicalConversationId ?? targetConversationId,
               !todoStore.canonicalTodos(for: syncId).isEmpty {
                let canonicalTodos = todoStore.canonicalTodos(for: syncId)
                chatStore.syncPlanStepsFromCanonicalTodos(canonicalTodos, in: syncId)
            }
        } else if !isBuildScoped {
            todoStore.upsertFromAgent(
                id: nil,
                title: title,
                status: todoStatus,
                priority: nil,
                notes: nil,
                activeForm: stepActiveForm,
                linkedFiles: [],
                conversationId: targetConversationId
            )
            if todoStatus == .done {
                _ = todoStore.advanceNextRuntimeTodoIfNeeded(conversationId: targetConversationId)
            }
        }
    }
}
