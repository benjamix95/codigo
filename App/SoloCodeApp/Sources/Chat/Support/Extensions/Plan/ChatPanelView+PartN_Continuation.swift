import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    internal func continueIfPrematureStub(
        initial: String,
        provider: any LLMProvider,
        originalPrompt: String,
        context: WorkspaceContext,
        conversationId: UUID,
        hideContentDuringPlanDiscovery: Bool = false
    ) async throws -> String {
        var combinedText = initial
        let maxAutoContinuationRounds = 3
        var round = 0

        while round < maxAutoContinuationRounds {
            let runtimeSnapshot = flowCoordinator.prepareDirectStreamContinuation(
                originalPrompt: originalPrompt,
                currentText: combinedText
            )
            guard let continuationPrompt = runtimeSnapshot?.output?.followUpPrompt else {
                break
            }
            round += 1
            if let runtimeSnapshot {
                flowCoordinator.setDirectRuntimeSnapshot(runtimeSnapshot)
            }

            let prior = combinedText
            let followUp = try await flowCoordinator.runStream(
                provider: provider,
                prompt: continuationPrompt,
                context: context,
                attachments: nil,
                onText: { deltaFull in
                    let combined = prior + "\n" + deltaFull
                    let displayContent = hideContentDuringPlanDiscovery
                        ? "Planning in progress… Open the Planning panel to see the result."
                        : combined
                    applyStreamingUpdate(
                        content: displayContent,
                        conversationId: conversationId
                    )
                },
                onRaw: { t, p, pid in
                    handleRawStreamEvent(type: t, payload: p, providerId: pid, conversationId: conversationId)
                },
                onError: { content in
                    DispatchQueue.main.async {
                        let combined = prior + "\n" + content
                        chatStore.updateLastAssistantMessage(content: combined, in: conversationId)
                    }
                },
                onSignal: nil
            )

            combinedText = prior + "\n" + followUp
        }

        return combinedText
    }

    internal func ensurePlanRuntimeSnapshot(shouldRunInline: Bool) -> MainChatRuntimeSnapshotBridge {
        if let snapshot = flowCoordinator.planRuntimeSnapshotState() {
            return snapshot
        }
        return MainChatRuntimeSnapshotBridge(
            turnState: MainChatBridgeState(
                conversationId: conversationId ?? UUID(),
                assistantMessageId: UUID(),
                turnId: (conversationId ?? UUID()).uuidString,
                providerId: providerRegistry.selectedProviderId,
                sequence: 0,
                isStreaming: false,
                startedAt: nil,
                completedAt: nil,
                updatedAt: nil,
                status: "idle",
                orderedTextStreamIds: [],
                textByStreamId: [:],
                reasoningByGroupId: [:],
                artifacts: []
            ),
            mode: .plan,
            directStream: nil,
            plan: MainChatPlanSnapshotBridge(
                phase: mapPlanPhase(planFlowPhase),
                planningStateKind: mapPlanningStateKind(planningState),
                clarificationQuestions: currentClarificationQuestions(),
                proposalContent: currentProposalContent(),
                optionFullTexts: currentProposalOptions().map(\.fullText),
                userRequest: planUserRequest,
                analysisContext: planAnalysisContext,
                clarificationAnswers: planClarificationAnswers,
                clarificationCycles: planClarificationCycles,
                questionEpoch: planQuestionToolEpoch(for: conversationId ?? UUID()),
                shouldRunInline: shouldRunInline
            ),
            output: nil
        )
    }

    internal func applyPlanRuntimeSnapshot(_ snapshot: MainChatRuntimeSnapshotBridge) {
        guard let plan = snapshot.plan else { return }
        flowCoordinator.setPlanRuntimeSnapshot(snapshot)
        if let phase = plan.phase {
            planFlowPhase = phase.asSwiftPhase
        }
        if let kind = plan.planningStateKind {
            switch kind {
            case .idle:
                planningState = .idle
            case .awaitingClarification:
                planningState = .awaitingClarification(questions: plan.clarificationQuestions ?? "")
            case .awaitingChoice:
                let options = plan.optionFullTexts.flatMap { text in
                    let strict = PlanOptionsParser.parseStrict(from: text)
                    return strict.isEmpty ? PlanOptionsParser.parse(from: text) : strict
                }
                planningState = .awaitingChoice(planContent: plan.proposalContent ?? "", options: options)
            }
        }
        planUserRequest = plan.userRequest
        planAnalysisContext = plan.analysisContext
        planClarificationAnswers = plan.clarificationAnswers
        planClarificationCycles = plan.clarificationCycles
    }

    internal func planRuntimeAction(
        _ action: String,
        text: String? = nil,
        questions: String? = nil,
        planContent: String? = nil,
        optionFullTexts: [String] = [],
        shouldRunInline: Bool
    ) -> MainChatRuntimeSnapshotBridge? {
        let snapshot = ensurePlanRuntimeSnapshot(shouldRunInline: shouldRunInline)
        let next = flowCoordinator.callRuntimeAction(
            action: action,
            snapshot: snapshot,
            text: text,
            questions: questions,
            planContent: planContent,
            optionFullTexts: optionFullTexts,
            shouldRunInline: shouldRunInline
        )
        if let next {
            applyPlanRuntimeSnapshot(next)
        }
        return next
    }

    private func currentClarificationQuestions() -> String? {
        if case .awaitingClarification(let questions) = planningState {
            return questions
        }
        return nil
    }

    private func currentProposalContent() -> String? {
        if case .awaitingChoice(let planContent, _) = planningState {
            return planContent
        }
        return nil
    }

    private func currentProposalOptions() -> [PlanOption] {
        if case .awaitingChoice(_, let options) = planningState {
            return options
        }
        return []
    }

    private func mapPlanningStateKind(_ state: PlanningState) -> MainChatPlanningStateKindBridge {
        switch state {
        case .idle:
            return .idle
        case .awaitingClarification:
            return .awaitingClarification
        case .awaitingChoice:
            return .awaitingChoice
        }
    }

    private func mapPlanPhase(_ phase: PlanFlowPhase) -> MainChatPlanPhaseBridge {
        switch phase {
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
