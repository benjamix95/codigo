import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers
extension ChatPanelView {
    @MainActor
    internal func handleLegacyPlanStepUpdateEvent(
        stepId: String,
        status: PlanStepStatus,
        stepTitle: String?,
        conversationId: UUID?
    ) {
        enableTaskPanelIfNeeded()
        let targetId = resolvePlanStepTargetConversationId(
            eventConversationId: conversationId,
            activeBuildPlanConversationId: activeBuildPlanConversationId,
            activeTaskConversationId: chatStore.activeTaskConversationId
        )
        chatStore.upsertPlanStep(stepId: stepId, status: status, title: stepTitle, in: targetId)
        if shouldMirrorLegacyPlanStepIntoActiveBuildPlan(
            targetConversationId: targetId,
            phase: planFlowPhase,
            activeBuildPlanConversationId: activeBuildPlanConversationId,
            activeBuildAgentConversationId: activeBuildAgentConversationId
        ), let sourcePlanId = activeBuildPlanConversationId {
            chatStore.upsertPlanStep(stepId: stepId, status: status, title: stepTitle, in: sourcePlanId)
        }
        syncCanonicalTodoFromPlanStep(
            title: stepTitle,
            status: status,
            targetConversationId: targetId
        )
    }
    @MainActor
    internal func handlePlanCreateEvent(
        goal: String,
        chosenPath: String?,
        steps: [PlanStepUpsertPayload],
        eventConversationId: String?,
        fallbackConversationId: UUID?
    ) {
        enableTaskPanelIfNeeded()
        chatStore.applyPlanCreate(
            goal: goal,
            chosenPath: chosenPath,
            steps: steps,
            conversationId: eventConversationId
        )
        let targetId = resolvePlanMutationConversationId(
            rawConversationId: eventConversationId,
            fallbackConversationId: fallbackConversationId
        )
        if let targetId, let board = chatStore.planBoard(for: targetId) {
            for step in board.steps {
                syncCanonicalTodoFromPlanStep(
                    title: step.title,
                    status: step.status,
                    targetConversationId: targetId
                )
            }
        }
        if shouldAutoOpenPlanPanel(trigger: .flowStarted), !showPlanPanel {
            openPlanPanelForCurrentContext(
                preserveHistorySelection: false,
                source: .automaticFlow
            )
        }
    }

    @MainActor
    internal func handlePlanStepUpsertEvent(
        _ payload: PlanStepUpsertPayload,
        fallbackConversationId: UUID?
    ) {
        enableTaskPanelIfNeeded()
        chatStore.applyPlanStepUpsert(payload, fallbackConversationId: fallbackConversationId)
        let targetId = resolvePlanMutationConversationId(
            rawConversationId: payload.conversationId,
            fallbackConversationId: fallbackConversationId
        )
        syncCanonicalTodoFromPlanStep(
            title: payload.title,
            status: payload.status,
            targetConversationId: targetId
        )
    }
    @MainActor
    internal func handlePlanStepBatchUpdateEvent(
        items: [PlanStepBatchUpdateItemPayload],
        conversationId rawConversationId: String?,
        fallbackConversationId: UUID?
    ) {
        enableTaskPanelIfNeeded()
        chatStore.applyPlanStepBatchUpdate(
            items: items,
            conversationId: rawConversationId,
            fallbackConversationId: fallbackConversationId
        )
        let targetId = resolvePlanMutationConversationId(
            rawConversationId: rawConversationId,
            fallbackConversationId: fallbackConversationId
        )
        for item in items {
            let title = inferredPlanStepTitle(
                candidate: item.title,
                stepId: item.stepId,
                conversationId: targetId
            )
            syncCanonicalTodoFromPlanStep(
                title: title,
                status: item.status,
                targetConversationId: targetId
            )
        }
    }
    @MainActor
    internal func handlePlanStepReorderEvent(
        orderedStepIds: [String],
        conversationId rawConversationId: String?,
        fallbackConversationId: UUID?
    ) {
        enableTaskPanelIfNeeded()
        chatStore.applyPlanStepReorder(
            orderedStepIds: orderedStepIds,
            conversationId: rawConversationId,
            fallbackConversationId: fallbackConversationId
        )
    }

    @MainActor
    internal func handlePlanStepDependencySetEvent(
        stepId: String,
        dependsOn: [String],
        conversationId rawConversationId: String?,
        fallbackConversationId: UUID?
    ) {
        enableTaskPanelIfNeeded()
        chatStore.applyPlanStepDependencySet(
            stepId: stepId,
            dependsOn: dependsOn,
            conversationId: rawConversationId,
            fallbackConversationId: fallbackConversationId
        )
    }

    @MainActor
    internal func handlePlanSetWalkthroughEvent(
        markdown: String,
        summary: String?,
        outcome: String,
        conversationId rawConversationId: String?,
        fallbackConversationId: UUID?
    ) {
        enableTaskPanelIfNeeded()
        chatStore.applyPlanSetWalkthrough(
            markdown: markdown,
            summary: summary,
            outcome: outcome,
            conversationId: rawConversationId,
            fallbackConversationId: fallbackConversationId
        )
    }

    @MainActor
    internal func handlePlanRequestUserInputEvent(
        _ payload: PlanRequestUserInputPayload,
        fallbackConversationId: UUID?
    ) {
        enableTaskPanelIfNeeded()

        guard let targetConversationId = resolvePlanMutationConversationId(
            rawConversationId: payload.conversationId,
            fallbackConversationId: fallbackConversationId
        ) else {
            return
        }

        let questionsMarkdown = PlanClarificationQuestionnaireMarkdown.render(
            questionnaire: payload.questionnaire
        )
        chatStore.updateLastAssistantMessage(
            content: "Questions ready — answer in the plan panel.",
            in: targetConversationId,
            persistImmediately: true
        )
        chatStore.setLastAssistantStreaming(false, in: targetConversationId)
        _ = incrementPlanQuestionToolEpoch(
            for: targetConversationId,
            globalEpoch: &planQuestionToolRequestEpoch
        )
        guard shouldMutatePlanState(
            targetConversationId: targetConversationId,
            currentConversationId: self.conversationId
        ) else {
            planStreamingContentByConversation[targetConversationId] =
                normalizedPlanStreamingSnapshot(questionsMarkdown)
            return
        }
        planClarificationCycles += 1
        planFlowPhase = .questioning
        planningState = .awaitingClarification(questions: questionsMarkdown)
        updatePlanStreamingContent(questionsMarkdown, conversationId: targetConversationId)

        if shouldAutoOpenPlanPanel(trigger: .awaitingClarification), !showPlanPanel {
            openPlanPanelForCurrentContext(
                preserveHistorySelection: false,
                source: .automaticFlow
            )
        }
    }
}

private extension ChatPanelView {
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
        if !updated, !isBuildScoped {
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
        }
    }
}
