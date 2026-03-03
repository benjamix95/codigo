import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    internal func finalChatActionButton(
        icon: String,
        title: String,
        help: String,
        foreground: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.45))
            )
            .overlay(
                Capsule()
                    .strokeBorder(Color.primary.opacity(0.04), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(title)
    }

    internal func enableTaskPanelIfNeeded() {
        guard shouldEnableTaskPanelForMode(coderMode) else { return }
        if !taskPanelEnabled {
            taskPanelEnabled = true
        }
    }

    internal func scheduleFallbackTurnStartEvent(conversationId: UUID, providerId: String) {
        fallbackTurnStartWorkItem?.cancel()
        let work = DispatchWorkItem {
            Task { @MainActor in
                guard chatStore.isTaskActive(for: conversationId) else { return }
                guard taskActivityStore.activities.isEmpty else { return }
                recordTaskActivity(
                    type: "turn_started",
                    payload: [
                        "title": "Turn started",
                        "detail": "Request execution in progress",
                        "status": "started",
                        "group_id": "ui-fallback-\(conversationId.uuidString)",
                    ],
                    providerId: providerId,
                    conversationId: conversationId
                )
            }
        }
        fallbackTurnStartWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    internal func cancelFallbackTurnStartEvent() {
        fallbackTurnStartWorkItem?.cancel()
        fallbackTurnStartWorkItem = nil
    }

    internal func liveScrollTarget() -> AnyHashable? {
        guard isLoadingForCurrentConversation else { return nil }
        return AnyHashable(chatScrollBottomAnchorId)
    }

    internal var liveTraceEventCount: Int {
        guard let conv = chatStore.conversation(for: conversationId),
              let lastAssistant = conv.messages.last(where: { $0.role == .assistant }) else {
            return 0
        }
        return toolTraceStore.events(
            conversationId: conv.id,
            assistantMessageId: lastAssistant.id
        ).count
    }

    internal var scopedTaskActivityCount: Int {
        scopedTaskActivities(for: conversationId).count
    }

    @ViewBuilder
    internal func subagentCardsSection(message: ChatMessage, isLatestAssistant: Bool) -> some View {
        let liveCards: [SwarmLiveCardState] = (isLatestAssistant && isLoadingForCurrentConversation)
            ? visibleSwarmCardsForChat(from: taskActivityStore.swarmCardStates())
            : []
        let hasLiveCards = !liveCards.isEmpty

        if hasLiveCards {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(liveCards) { card in
                    SubagentChatCardView(
                        card: card,
                        onOpenInPanel: {
                            selectedSwarmId = card.swarmId
                            showSwarmPanel = true
                        },
                        onStop: {
                            lastTaskEndedByManualStop = true
                            interruptTask()
                        }
                    )
                }
            }
            .padding(.horizontal, 2)
        }
        // Show persisted snapshot cards when live cards aren't available.
        // This avoids a gap where neither live nor snapshot cards are visible.
        if !hasLiveCards, let snapshots = message.subagentCards, !snapshots.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(snapshots) { snapshot in
                    SubagentSnapshotCardView(snapshot: snapshot)
                }
            }
            .padding(.horizontal, 2)
        }
    }

    @ViewBuilder
    internal func messageTraceView(
        traceEvents: [ToolTraceEvent],
        effectiveContext: EffectiveContext
    ) -> some View {
        MessageToolTraceView(
            events: traceEvents,
            workspaceHints: traceWorkspaceHints(for: effectiveContext),
            onOpenFile: { openFilesStore.openFile($0) },
            onInteractionStart: {
                guard isLoadingForCurrentConversation else { return }
                isFollowingLive = false
            }
        )
    }

    internal func traceWorkspaceHints(for effectiveContext: EffectiveContext) -> [String] {
        let fromContext = effectiveContext.context?.folderPaths
            .filter { !$0.isEmpty } ?? []
        if !fromContext.isEmpty {
            return fromContext
        }
        if let primary = effectiveContext.primaryPath, !primary.isEmpty {
            return [primary]
        }
        return []
    }

    internal func latestMessageScrollTarget() -> AnyHashable? {
        guard chatStore.conversation(for: conversationId)?.messages.last != nil else { return nil }
        return AnyHashable(chatScrollBottomAnchorId)
    }

    internal func scheduleAutoScroll(
        proxy: ScrollViewProxy,
        target: AnyHashable,
        animated: Bool = false,
        delay: TimeInterval = 0.08
    ) {
        let now = Date()
        let sinceLastScroll = now.timeIntervalSince(lastAutoScrollAt)
        if lastAutoScrollTarget == target, sinceLastScroll < 0.10 {
            return
        }
        lastAutoScrollTarget = target
        lastAutoScrollAt = now
        autoScrollWorkItem?.cancel()
        let work = DispatchWorkItem {
            if animated {
                withAnimation(.easeOut(duration: 0.14)) {
                    proxy.scrollTo(target, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(target, anchor: .bottom)
            }
        }
        autoScrollWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    internal func interruptTask() {
        interruptTask(for: conversationId)
    }

    @MainActor
    internal func launchRunTask(
        for conversationId: UUID,
        operation: @escaping () async -> Void
    ) {
        activeRunTaskByConversation[conversationId]?.cancel()
        let token = UUID()
        activeRunTokenByConversation[conversationId] = token

        let task = Task { @MainActor in
            await operation()
            guard activeRunTokenByConversation[conversationId] == token else { return }
            activeRunTokenByConversation.removeValue(forKey: conversationId)
            activeRunTaskByConversation.removeValue(forKey: conversationId)
        }
        activeRunTaskByConversation[conversationId] = task
    }

    @MainActor
    @discardableResult
    internal func cancelRunTask(for conversationId: UUID?) -> Bool {
        guard let conversationId else { return false }
        guard let task = activeRunTaskByConversation[conversationId] else { return false }
        task.cancel()
        activeRunTaskByConversation.removeValue(forKey: conversationId)
        activeRunTokenByConversation.removeValue(forKey: conversationId)
        return true
    }

    @MainActor
    internal func applyFlowCoordinatorState(
        for targetConversationId: UUID?,
        _ transition: (ConversationFlowCoordinator) -> Void
    ) {
        guard targetConversationId == conversationId else { return }
        transition(flowCoordinator)
    }

    /// Snapshots current swarm cards into the last assistant message, then ends the task.
    /// Flushes pending streaming content first to ensure no data is lost.
    @MainActor
    internal func snapshotSubagentCardsAndEndTask(conversationId targetConversationId: UUID?) {
        // Flush any pending streamed content so the assistant message is up-to-date
        // before we attach subagent cards or end the task.
        flushStreamingContent()

        // Flush pending task activities so subagent swarm cards are fully
        // populated before we snapshot them into the assistant message.
        flushPendingTaskActivities()
        taskActivityStore.flushPending()

        // Transition any cards still stuck in .running to .completed
        // so the panel doesn't show stale running indicators.
        taskActivityStore.finalizeRunningSwarmCards()

        let cards = visibleSwarmCardsForChat(from: taskActivityStore.swarmCardStates())
            .map { SubagentCardSnapshot(from: $0) }
        if !cards.isEmpty {
            chatStore.saveSubagentCardsToLastAssistant(cards, in: targetConversationId)
        }
        chatStore.endTask(conversationId: targetConversationId)
        // Force immediate persistence so the final state (cards + content)
        // survives an app crash right after task completion.
        chatStore.saveConversationsImmediately()
    }

    internal func visibleSwarmCardsForChat(from cards: [SwarmLiveCardState]) -> [SwarmLiveCardState] {
        return cards
    }

    internal func interruptTask(for targetConversationId: UUID?) {
        var didCancelTask = cancelRunTask(for: targetConversationId)
        if !didCancelTask, let target = targetConversationId,
           activeBuildPlanConversationId == target,
           let agentId = activeBuildAgentConversationId {
            didCancelTask = cancelRunTask(for: agentId)
        }
        if !didCancelTask {
            let scope = executionScopeForActiveTask()
            executionController.terminate(scope: scope)
        }
        applyFlowCoordinatorState(for: targetConversationId) { $0.interrupt() }
        taskFlushTask?.cancel()
        taskFlushTask = nil
        flushPendingTaskActivities()
        if let cid = targetConversationId {
            let cur =
                chatStore.conversation(for: cid)?.messages.last(where: {
                    $0.role == .assistant
                })?.content ?? ""
            chatStore.updateLastAssistantMessage(
                content: cur.isEmpty
                    ? "[Interrupted by user]"
                    : cur + "\n\n[Interrupted by user]", in: cid)
            chatStore.setLastAssistantStreaming(false, in: cid)
            clearStreamingReasoning(for: cid)
        }
        finalizeToolTraceTurn(conversationId: targetConversationId, outcome: .aborted)
        if targetConversationId == conversationId {
            cancelFallbackTurnStartEvent()
        }
        snapshotSubagentCardsAndEndTask(conversationId: targetConversationId)
        if activeBuildPlanConversationId == targetConversationId {
            activeBuildPlanConversationId = nil
        }
        if targetConversationId == conversationId {
            resetPlanFlowAfterInterruption()
        }
    }

    internal func resetPlanFlowAfterInterruption() {
        switch planFlowPhase {
        case .building:
            planFlowPhase = .readyToBuild
            clearPlanStreamingState()
        case .proposalReady:
            break
        case .analyzing, .questioning, .generating:
            planFlowPhase = .idle
            planningState = .idle
            clearPlanStreamingState()
        default:
            break
        }
    }

    internal func executionScopeForCurrentMode() -> ExecutionScope {
        switch coderMode {
        case .codeReviewMultiSwarm: return .review
        case .plan: return .plan
        default: return .agent
        }
    }

    internal func executionScopeForActiveTask() -> ExecutionScope {
        executionController.activeScope ?? executionScopeForCurrentMode()
    }

    internal func pauseOrResumeActiveTask() {
        let scope = executionScopeForActiveTask()
        let previousRunState = executionController.runState
        if previousRunState == .paused {
            executionController.resume(scope: scope)
            guard executionController.runState == .running else { return }
            taskActivityStore.markResumed()
            taskActivityStore.addActivity(
                TaskActivity(
                    type: "process_resumed",
                    title: "Process resumed",
                    detail: "Execution resumed by user",
                    payload: [:],
                    phase: .executing,
                    isRunning: true
                )
            )
            return
        }

        executionController.pause(scope: scope)
        guard executionController.runState == .paused else { return }
        taskActivityStore.markPaused()
        taskActivityStore.addActivity(
            TaskActivity(
                type: "process_paused",
                title: "Process paused",
                detail: "Execution paused by user",
                payload: [:],
                phase: .planning,
                isRunning: false
            )
        )
    }

    internal func handleVoiceAction() {
        if isLoadingForCurrentConversation {
            return
        }
        switch voiceInputController.state {
        case .idle, .failed:
            voiceInputController.start { transcript in
                let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                if inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    inputText = trimmed
                } else {
                    inputText = inputText + (inputText.hasSuffix(" ") ? "" : " ") + trimmed
                }
                isInputFocused = true
            }
        case .listening:
            voiceInputController.stop()
        case .requestingPermission, .transcribing:
            break
        }
    }

    internal func currentInstructionPolicyBundle() -> InstructionPolicyBundle {
        let hints = traceWorkspaceHints(for: effectiveContext)
        return InstructionPolicyBundle.load(workspacePaths: hints)
    }

    internal func expectedPolicyAckHash() -> String? {
        guard agentsHardBlockEnabled else { return nil }
        let bundle = currentInstructionPolicyBundle()
        let hash = bundle.policyHash.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hash.isEmpty else { return nil }
        return hash
    }

    internal func initializePolicyAckStateIfNeeded(for assistantMessageId: UUID) {
        guard let expectedHash = expectedPolicyAckHash() else {
            policyAckStateByMessage.removeValue(forKey: assistantMessageId)
            policyAckFailedMessages.remove(assistantMessageId)
            return
        }
        guard !policyAckFailedMessages.contains(assistantMessageId) else { return }
        if policyAckStateByMessage[assistantMessageId] == nil {
            policyAckStateByMessage[assistantMessageId] = PolicyAckState(expectedHash: expectedHash)
        }
    }

    @MainActor
    internal func startToolTraceTurn(conversationId: UUID, assistantMessageId: UUID, providerId: String) {
        if let previous = activeToolTraceTurnsByConversation[conversationId],
           previous.assistantMessageId != assistantMessageId {
            let previousEvents = toolTraceStore.events(
                conversationId: previous.conversationId,
                assistantMessageId: previous.assistantMessageId
            )
            let hasRunningOperations = previousEvents.contains(where: \.isRunning)
            let rolloverOutcome: ToolTraceTurnOutcome = hasRunningOperations ? .aborted : .success
            finalizeAutoTodoIfNeeded(
                messageId: previous.assistantMessageId,
                outcome: rolloverOutcome,
                providerId: previous.providerId,
                conversationId: previous.conversationId
            )
            toolTraceStore.finalizeTurn(
                conversationId: previous.conversationId,
                assistantMessageId: previous.assistantMessageId
            )
            toolTraceNextSequenceByMessage.removeValue(forKey: previous.assistantMessageId)
            toolTraceOperationalSeenByMessage.removeValue(forKey: previous.assistantMessageId)
            toolTraceOperationalCountByMessage.removeValue(forKey: previous.assistantMessageId)
            policyAckStateByMessage.removeValue(forKey: previous.assistantMessageId)
            // Flush any remaining blocked events before discarding the queue
            if let remainingQueued = policyAckBlockedQueue.removeValue(forKey: previous.assistantMessageId), !remainingQueued.isEmpty {
                if !policyAckFailedMessages.contains(previous.assistantMessageId) {
                    for event in remainingQueued {
                        recordTaskActivity(
                            type: event.type,
                            payload: event.payload,
                            providerId: event.providerId,
                            conversationId: event.conversationId
                        )
                    }
                }
            }
            policyAckFailedMessages.remove(previous.assistantMessageId)
            autoTodoIdByMessage.removeValue(forKey: previous.assistantMessageId)
            autoTodoCompletedOperationsByMessage.removeValue(forKey: previous.assistantMessageId)
            didReceiveExplicitTodoByMessage.remove(previous.assistantMessageId)
        }
        let turn = ToolTraceTurnContext(
            conversationId: conversationId,
            assistantMessageId: assistantMessageId,
            providerId: providerId
        )
        activeToolTraceTurnsByConversation[conversationId] = turn
        toolTraceNextSequenceByMessage[assistantMessageId] = 1
        toolTraceOperationalSeenByMessage[assistantMessageId] = false
        toolTraceOperationalCountByMessage[assistantMessageId] = 0
        autoTodoIdByMessage.removeValue(forKey: assistantMessageId)
        autoTodoCompletedOperationsByMessage.removeValue(forKey: assistantMessageId)
        didReceiveExplicitTodoByMessage.remove(assistantMessageId)
        if isSwarmPolicyAckExemptProvider(providerId) {
            policyAckStateByMessage.removeValue(forKey: assistantMessageId)
            policyAckFailedMessages.remove(assistantMessageId)
        } else {
            initializePolicyAckStateIfNeeded(for: assistantMessageId)
        }
        toolTraceStore.startTurn(
            conversationId: conversationId,
            assistantMessageId: assistantMessageId,
            providerId: providerId
        )
    }

    @MainActor
    internal func finalizeToolTraceTurn(conversationId: UUID?, outcome: ToolTraceTurnOutcome? = nil) {
        let finalOutcome = outcome ?? toolTraceTurnOutcome(for: flowCoordinator.state)

        if let conversationId {
            guard let active = activeToolTraceTurnsByConversation[conversationId] else { return }
            finalizeToolTraceTurn(active, outcome: finalOutcome)
            activeToolTraceTurnsByConversation.removeValue(forKey: conversationId)
            return
        }

        let activeTurns = Array(activeToolTraceTurnsByConversation.values)
        for active in activeTurns {
            finalizeToolTraceTurn(active, outcome: finalOutcome)
        }
        activeToolTraceTurnsByConversation.removeAll()
    }

}
