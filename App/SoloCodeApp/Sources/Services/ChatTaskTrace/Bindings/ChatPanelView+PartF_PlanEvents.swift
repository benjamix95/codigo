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
            conversationId: eventConversationId,
            fallbackConversationId: fallbackConversationId
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
        if shouldInvalidateChatTimelineForLiveMutation(eventType: "plan_create") {
            streamContentVersion &+= 1
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
        if shouldInvalidateChatTimelineForLiveMutation(eventType: "plan_step_upsert") {
            streamContentVersion &+= 1
        }
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
        if shouldInvalidateChatTimelineForLiveMutation(eventType: "plan_step_batch_update") {
            streamContentVersion &+= 1
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
        if shouldInvalidateChatTimelineForLiveMutation(eventType: "plan_step_reorder") {
            streamContentVersion &+= 1
        }
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
        if shouldInvalidateChatTimelineForLiveMutation(eventType: "plan_step_dependency_set") {
            streamContentVersion &+= 1
        }
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
        if shouldInvalidateChatTimelineForLiveMutation(eventType: "plan_set_walkthrough") {
            streamContentVersion &+= 1
        }
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
        if shouldInvalidateChatTimelineForLiveMutation(eventType: "plan_request_user_input") {
            streamContentVersion &+= 1
        }
    }
}
