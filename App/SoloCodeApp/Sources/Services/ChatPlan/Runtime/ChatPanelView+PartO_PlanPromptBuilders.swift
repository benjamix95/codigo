import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    internal func planRuntimeAction(
        _ action: String,
        text: String? = nil,
        questions: String? = nil,
        planContent: String? = nil,
        optionFullTexts: [String] = [],
        shouldRunInline: Bool
    ) -> MainChatRuntimeSnapshotBridge? {
        let intent = action == "plan_receive_clarification_questions"
            ? "plan_receive_clarification_questions"
            : "apply_plan_runtime_action"
        var payload: [String: String] = ["should_run_inline": shouldRunInline ? "true" : "false"]
        if intent == "apply_plan_runtime_action" {
            payload["action"] = action
        }
        if let questions, !questions.isEmpty {
            payload["questions"] = questions
        }
        if let planContent, !planContent.isEmpty {
            payload["plan_content"] = planContent
        }
        if !optionFullTexts.isEmpty {
            payload["option_full_texts"] = encodePlanOptionTexts(optionFullTexts)
        }
        let response = applyPlanUIIntent(
            intent,
            conversationId: conversationId,
            text: action == "plan_receive_clarification_questions" ? questions : text,
            payload: payload
        )
        return response?.state?.runtimeSnapshot
    }

    @discardableResult
    internal func applyPlanUIIntent(
        _ intent: String,
        conversationId targetConversationId: UUID?,
        text: String? = nil,
        payload: [String: String] = [:]
    ) -> MainChatUIIntentResponseBridge? {
        let request = MainChatUIIntentRequestBridge(
            schemaVersion: 1,
            intent: intent,
            state: RustMainChatStoreAdapter.uiState(
                from: chatStore,
                runtimeSnapshot: flowCoordinator.planRuntimeSnapshotState()
                    ?? flowCoordinator.directRuntimeSnapshotState(),
                selectedConversationId: targetConversationId ?? conversationId,
                draftText: inputText,
                planPanelVisible: showPlanPanel,
                followLive: isFollowingLive,
                collapsedArtifactsByTurn: collapsedArtifactsByTurn
            ),
            conversationId: (targetConversationId ?? conversationId)?.uuidString.lowercased(),
            turnId: nil,
            artifactId: nil,
            text: text,
            timestamp: Date(),
            payload: payload
        )
        guard let response = RustMainChatStoreAdapter.applyUIIntent(request, to: chatStore) else {
            return nil
        }
        applyPlanStateMirror(
            planSnapshot: response.snapshot?.plan,
            runtimeSnapshot: response.state?.runtimeSnapshot,
            conversationId: targetConversationId ?? conversationId
        )
        return response
    }

    internal func projectPlanningSnapshot(
        conversationId targetConversationId: UUID?
    ) -> (snapshot: MainChatUISnapshotBridge, state: MainChatUIStateBridge)? {
        let state = RustMainChatStoreAdapter.uiState(
            from: chatStore,
            runtimeSnapshot: flowCoordinator.planRuntimeSnapshotState()
                ?? flowCoordinator.directRuntimeSnapshotState(),
            selectedConversationId: targetConversationId ?? conversationId,
            draftText: inputText,
            planPanelVisible: showPlanPanel,
            followLive: isFollowingLive,
            collapsedArtifactsByTurn: collapsedArtifactsByTurn
        )
        guard let snapshot = RustMainChatStoreAdapter.projectUI(state) else { return nil }
        return (snapshot, state)
    }

    internal func syncPlanPanelVisibilityToRust(_ isVisible: Bool) {
        _ = applyPlanUIIntent(
            "set_plan_panel_visible",
            conversationId: conversationId,
            payload: ["visible": isVisible ? "true" : "false"]
        )
    }

    internal func applyPlanStateMirror(
        planSnapshot: MainChatUIPlanSnapshotBridge?,
        runtimeSnapshot: MainChatRuntimeSnapshotBridge?,
        conversationId targetConversationId: UUID?
    ) {
        if let runtimeSnapshot {
            flowCoordinator.setPlanRuntimeSnapshot(runtimeSnapshot)
            if let plan = runtimeSnapshot.plan {
                planUserRequest = plan.userRequest
                planAnalysisContext = plan.analysisContext
                planClarificationAnswers = plan.clarificationAnswers
                planClarificationQuestionnaire = plan.clarificationQuestionnaire
                planClarificationCycles = plan.clarificationCycles
                planShouldRunInline = plan.shouldRunInline
                planQuestionToolRequestEpoch = max(planQuestionToolRequestEpoch, plan.questionEpoch)
            }
        }
        guard let planSnapshot else { return }
        showPlanPanel = planSnapshot.isVisible
        planFlowPhase = planSnapshot.phase?.asSwiftPhase ?? .idle
        switch planSnapshot.planningStateKind ?? .idle {
        case .idle:
            planningState = .idle
            planClarificationQuestionnaire = nil
        case .awaitingClarification:
            planClarificationQuestionnaire = planSnapshot.clarificationQuestionnaire
            planningState = .awaitingClarification(
                questions: planSnapshot.clarificationQuestions ?? ""
            )
        case .awaitingChoice:
            planClarificationQuestionnaire = nil
            let options = planOptionsFromSnapshot(
                titles: planSnapshot.optionTitles,
                fullTexts: planSnapshot.optionFullTexts
            )
            planningState = .awaitingChoice(
                planContent: planSnapshot.proposalContent ?? "",
                options: options
            )
        }
        if let targetConversationId {
            planStreamingContent = planStreamingContentByConversation[targetConversationId] ?? ""
        }
    }

    internal func buildPhase0ScreeningPrompt(userRequest: String) -> String {
        planRuntimeAction(
            "plan_prepare_phase0_screening_prompt",
            text: userRequest,
            shouldRunInline: planShouldRunInline
        )?.output?.generatedPrompt ?? ""
    }

    internal func buildPhase1AnalysisPrompt(userRequest: String) -> String {
        planRuntimeAction(
            "plan_prepare_phase1_analysis_prompt",
            text: userRequest,
            shouldRunInline: planShouldRunInline
        )?.output?.generatedPrompt ?? ""
    }

    internal func buildPostClarificationAnalysisPrompt(
        userRequest: String,
        analysisContext: String,
        clarificationAnswers: String
    ) -> String {
        if planAnalysisContext != analysisContext {
            _ = planRuntimeAction(
                "plan_store_analysis_context",
                text: analysisContext,
                shouldRunInline: planShouldRunInline
            )
        }
        if planClarificationAnswers != clarificationAnswers {
            _ = applyPlanUIIntent(
                "submit_clarification_answers",
                conversationId: conversationId,
                text: clarificationAnswers
            )
        }
        return planRuntimeAction(
            "plan_prepare_post_clarification_analysis_prompt",
            text: userRequest,
            shouldRunInline: planShouldRunInline
        )?.output?.generatedPrompt ?? ""
    }

    internal func buildPhase2QuestionPrompt(userRequest: String, analysisContext: String) -> String {
        if planAnalysisContext != analysisContext {
            _ = planRuntimeAction(
                "plan_store_analysis_context",
                text: analysisContext,
                shouldRunInline: planShouldRunInline
            )
        }
        return planRuntimeAction(
            "plan_prepare_phase2_questions_prompt",
            text: userRequest,
            shouldRunInline: planShouldRunInline
        )?.output?.generatedPrompt ?? ""
    }

    internal func buildPhase3GenerationPrompt(
        userRequest: String,
        analysisContext: String,
        clarificationAnswers: String
    ) -> String {
        if planAnalysisContext != analysisContext {
            _ = planRuntimeAction(
                "plan_store_analysis_context",
                text: analysisContext,
                shouldRunInline: planShouldRunInline
            )
        }
        if planClarificationAnswers != clarificationAnswers {
            _ = applyPlanUIIntent(
                "submit_clarification_answers",
                conversationId: conversationId,
                text: clarificationAnswers
            )
        }
        return planRuntimeAction(
            "plan_prepare_phase3_generation_prompt",
            text: userRequest,
            shouldRunInline: planShouldRunInline
        )?.output?.generatedPrompt ?? ""
    }

    internal func buildPhase3TodoComplianceRepairPrompt(
        userRequest: String,
        analysisContext: String,
        clarificationAnswers: String,
        invalidPlanOutput: String
    ) -> String {
        if planAnalysisContext != analysisContext {
            _ = planRuntimeAction(
                "plan_store_analysis_context",
                text: analysisContext,
                shouldRunInline: planShouldRunInline
            )
        }
        if planClarificationAnswers != clarificationAnswers {
            _ = applyPlanUIIntent(
                "submit_clarification_answers",
                conversationId: conversationId,
                text: clarificationAnswers
            )
        }
        return planRuntimeAction(
            "plan_prepare_phase3_repair_prompt",
            text: invalidPlanOutput,
            shouldRunInline: planShouldRunInline
        )?.output?.generatedPrompt ?? ""
    }

    private func encodePlanOptionTexts(_ optionFullTexts: [String]) -> String {
        let data = (try? JSONEncoder().encode(optionFullTexts)) ?? Data("[]".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    private func planOptionsFromSnapshot(
        titles: [String],
        fullTexts: [String]
    ) -> [PlanOption] {
        fullTexts.enumerated().map { index, fullText in
            PlanOption(
                id: index + 1,
                title: titles.indices.contains(index) ? titles[index] : "Option \(index + 1)",
                fullText: fullText
            )
        }
    }
}

private extension MainChatPlanPhaseBridge {
    var asSwiftPhase: PlanFlowPhase {
        switch self {
        case .idle: return .idle
        case .analyzing: return .analyzing
        case .questioning: return .questioning
        case .generating: return .generating
        case .proposalReady: return .proposalReady
        case .readyToBuild: return .readyToBuild
        case .building: return .building
        }
    }
}
