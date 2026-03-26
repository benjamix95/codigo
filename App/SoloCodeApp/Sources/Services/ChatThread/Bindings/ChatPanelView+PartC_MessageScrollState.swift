import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    /// Overlay “vuoto”: un solo punto di decisione con letture coerenti (stesso `conversationId`,
    /// stesso `chatStore`, stesso snapshot). Regola: **mai** coprire l’area se il numero di messaggi
    /// nello store è > 0 **oppure** lo snapshot (allineato o meno) ha ancora righe — la lista
    /// `chatMessagesAreaContent` usa lo snapshot, quindi l’overlay deve rispettarlo. Evidenza H2: log
    /// `empty_state_overlay_shown` con conteggi 4→6 non poteva essere vero nello stesso frame della
    /// decisione (likely desync `onChange` vs `let` sul modifier); questa policy elimina il caso.
    internal var shouldShowMessagesAreaEmptyState: Bool {
        guard !isLoadingForCurrentConversation else { return false }
        // Con zero thread selezionato, lo store non ha contesto: senza questo guard l’overlay
        // “vuoto” si attiva (storeCount 0, snapshot spesso vuoto) e copre tutta l’area. Se
        // `selectedConversationId` vira nil per un frame, effetto “chat sparita” (evidenza
        // fba6fd: empty_overlay_allowed con conversationId nil).
        guard conversationId != nil else { return false }

        let storeCount = chatStore.conversation(for: conversationId)?.messages.count ?? 0
        guard storeCount == 0 else { return false }

        let snap = messagesConversationSnapshot
        let aligned: Bool = {
            guard let cid = conversationId, let s = snap else { return false }
            return s.id == cid
        }()
        let snapCount = snap?.messages.count ?? 0

        if aligned {
            guard snapCount == 0 else { return false }
        } else if let s = snap, !s.messages.isEmpty {
            // Snapshot ancora di un altro thread ma la lista lo sta ancora mostrando: non coprire.
            return false
        }

        let result = true
        // #region agent log
        AgentDebugSessionNDJSONLog.appendThrottled(
            gateKey: "H2-empty-overlay-allowed",
            hypothesisId: "H2",
            location: "shouldShowMessagesAreaEmptyState",
            message: "empty_overlay_allowed",
            data: [
                "storeCount": "\(storeCount)",
                "snapCount": "\(snapCount)",
                "snapAligned": "\(aligned)",
                "conversationId": conversationId?.uuidString ?? "nil",
            ]
        )
        // #endregion
        return result
    }

    internal var messagesAreaEmptyStateOverlay: some View {
        Text("Ask anything, build anything")
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .offset(y: -40)
            .allowsHitTesting(false)
    }

    internal var messagesAreaIsEmpty: Bool {
        guard let conv = chatStore.conversation(for: conversationId) else { return true }
        return conv.messages.isEmpty
    }

    internal func handleStreamContentVersionChange(proxy: ScrollViewProxy) {
        guard isFollowingLive else { return }
        scheduleAutoScroll(proxy: proxy, target: chatScrollBottomAnchorId, delay: 0.04)
    }

    internal func handleMessagesCountChange(proxy: ScrollViewProxy) {
        guard isFollowingLive else { return }
        // Use a longer delay than streamContentVersion (0.04s) so that
        // during streaming, the content version handler handles the scroll
        // and this one gets coalesced by scheduleAutoScroll's throttle.
        // Previously both fired within 10ms of each other with animation,
        // causing duplicate layout passes.
        scheduleAutoScroll(proxy: proxy, target: chatScrollBottomAnchorId, delay: 0.12)
    }

    internal func handleLiveTraceEventsChange(proxy: ScrollViewProxy) {
        guard isLoadingForCurrentConversation, isFollowingLive else { return }
        if let target = liveScrollTarget() {
            // Use a slightly longer delay to let streamContentVersion
            // handle the primary scroll; this acts as a fallback.
            scheduleAutoScroll(proxy: proxy, target: target, delay: 0.14)
        }
    }

    internal func handlePlanningStateChange(_ newState: PlanningState, proxy: ScrollViewProxy) {
        if case .awaitingChoice = newState {
            if let target = latestMessageScrollTarget() {
                scheduleAutoScroll(proxy: proxy, target: target, animated: true, delay: 0)
            }
        } else if case .awaitingClarification = newState {
            if let target = latestMessageScrollTarget() {
                scheduleAutoScroll(proxy: proxy, target: target, animated: true, delay: 0)
            }
        }
    }

    internal func handleActiveTaskConversationChange(
        oldSet: Set<UUID>,
        newSet: Set<UUID>,
        proxy: ScrollViewProxy
    ) {
        guard let cid = conversationId else { return }
        let isActive = newSet.contains(cid)
        let wasActive = oldSet.contains(cid)
        if !wasActive && isActive {
            isFollowingLive = true
            if let target = liveScrollTarget() {
                scheduleAutoScroll(proxy: proxy, target: target, delay: 0)
            }
        } else if wasActive && !isActive {
            cancelFallbackTurnStartEvent()
            isFollowingLive = true
            if let target = latestMessageScrollTarget() {
                // Previously scheduled two overlapping scrolls (0s + 0.16s) with
                // animation. The double schedule raced with other handlers and
                // contributed to main thread saturation. A single delayed scroll
                // is sufficient — the 0.35s throttle in scheduleAutoScroll
                // prevents rapid-fire duplicates.
                scheduleAutoScroll(proxy: proxy, target: target, delay: 0.08)
            }
        }
    }

    internal func handleTaskActivitiesChange(proxy: ScrollViewProxy) {
        guard isLoadingForCurrentConversation, isFollowingLive else { return }
        if let target = liveScrollTarget() ?? latestMessageScrollTarget() {
            scheduleAutoScroll(proxy: proxy, target: target, delay: 0.08)
        }
    }

    @ViewBuilder
    internal var chatMessagesAreaContent: some View {
        // Finché `@State messagesConversationSnapshot` non è valorizzato, `onAppear`/`.onChange`
        // arrivano dopo il primo layout → un frame di placeholder vuoto (sfarfallio all’avvio).
        // Fallback allo store solo nello stato nil mantiene il primo paint coerente senza
        // dipendenza dal ramo snapshot quando quello è già presente.
        if let conv = messagesConversationSnapshot {
            messagesStack(for: conv)
        } else if let cid = conversationId, let live = chatStore.conversation(for: cid) {
            messagesStack(for: live)
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                Color.clear
                    .frame(height: 1)
                    .id(chatScrollTopAnchorId)
                Color.clear
                    .frame(height: 1)
                    .id(chatScrollBottomAnchorId)
            }
        }
    }

    /// Refresh conversation and loading snapshot from ObservableObjects.
    /// Called on every streamContentVersion change and messages.count change.
    internal func refreshMessagesSnapshot() {
        let fresh = chatStore.conversation(for: conversationId)

        // Always update loading state.
        let freshLoading = chatStore.isTaskActive(for: conversationId)
            || pipelineIntegrationService.isRunning(for: conversationId)
        if snapshotIsLoading != freshLoading {
            // #region agent log
            AgentDebugSessionNDJSONLog.append(
                hypothesisId: "H12",
                location: "refreshMessagesSnapshot",
                message: "snapshotIsLoading_edge",
                data: [
                    "from": "\(snapshotIsLoading)",
                    "to": "\(freshLoading)",
                    "conversationId": conversationId?.uuidString ?? "nil",
                    "streamContentVersion": "\(streaming.streamContentVersion)",
                ]
            )
            // #endregion
            snapshotIsLoading = freshLoading
        }

        let planBuilding =
            planFlowPhase == .building && activeBuildPlanConversationId == conversationId
        let chromeBusy = freshLoading || planBuilding
        if snapshotChromeLoading != chromeBusy {
            snapshotChromeLoading = chromeBusy
        }

        if let cid = conversationId {
            snapshotRootLayoutSwarmSteps = swarmProgressStore.steps(for: cid)
            snapshotRootLayoutSwarmCards = taskActivityStore.swarmCardStates(for: cid)
        } else {
            snapshotRootLayoutSwarmSteps = []
            snapshotRootLayoutSwarmCards = []
        }

        // Only update conversation if actually different.
        let snapshotCount = messagesConversationSnapshot?.messages.count ?? -1
        let freshCount = fresh?.messages.count ?? -1
        let snapshotLastContent = messagesConversationSnapshot?.messages.last?.content.count ?? -1
        let freshLastContent = fresh?.messages.last?.content.count ?? -1
        let snapshotLastReasoning = messagesConversationSnapshot?.messages.last?.reasoningText?.count ?? -1
        let freshLastReasoning = fresh?.messages.last?.reasoningText?.count ?? -1
        let snapshotLastStreaming = messagesConversationSnapshot?.messages.last?.isStreaming ?? false
        let freshLastStreaming = fresh?.messages.last?.isStreaming ?? false
        let snapshotLastBlocks = messagesConversationSnapshot?.messages.last?.blocks?.count ?? -1
        let freshLastBlocks = fresh?.messages.last?.blocks?.count ?? -1

        let needsSnapshotUpdate =
            messagesConversationSnapshot?.id != fresh?.id
            || snapshotCount != freshCount
            || snapshotLastContent != freshLastContent
            || snapshotLastReasoning != freshLastReasoning
            || snapshotLastStreaming != freshLastStreaming
            || snapshotLastBlocks != freshLastBlocks

        if needsSnapshotUpdate {
            let prevSnapId = messagesConversationSnapshot?.id.uuidString ?? "nil"
            messagesConversationSnapshot = fresh
            // #region agent log
            AgentDebugSessionNDJSONLog.appendThrottled(
                gateKey: "H8-snapshot-mutate",
                minInterval: 0.06,
                hypothesisId: "H8",
                location: "refreshMessagesSnapshot",
                message: "snapshot_state_replaced",
                data: [
                    "conversationId": conversationId?.uuidString ?? "nil",
                    "prevSnapId": prevSnapId,
                    "freshId": fresh?.id.uuidString ?? "nil",
                    "freshCount": "\(freshCount)",
                    "freshLastContentLen": "\(freshLastContent)",
                    "freshLastStreaming": "\(freshLastStreaming)",
                    "streamContentVersion": "\(streaming.streamContentVersion)",
                    "snapshotIsLoading": "\(snapshotIsLoading)",
                ]
            )
            // #endregion
        } else if snapshotIsLoading || freshLoading {
            // #region agent log
            AgentDebugSessionNDJSONLog.appendThrottled(
                gateKey: "H11-refresh-noop-stream",
                minInterval: 0.12,
                hypothesisId: "H11",
                location: "refreshMessagesSnapshot",
                message: "refresh_ran_but_snapshot_unchanged_while_active",
                data: [
                    "conversationId": conversationId?.uuidString ?? "nil",
                    "streamContentVersion": "\(streaming.streamContentVersion)",
                    "freshCount": "\(freshCount)",
                    "freshLastContentLen": "\(freshLastContent)",
                    "snapshotIsLoading": "\(snapshotIsLoading)",
                    "freshLoading": "\(freshLoading)",
                ]
            )
            // #endregion
        }

        // Throttle trace events refresh: only update at most every 250ms.
        // This prevents the barrier fingerprint from changing on every
        // streamContentVersion increment (215+ per session), which was
        // causing ~710 EQ-MISS. Text deltas are the most frequent
        // streamContentVersion source but don't affect trace events.
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - lastTraceRefreshTime
        if elapsed >= 0.25 || !snapshotIsLoading {
            refreshTraceEventsSnapshot(fresh: fresh)
            lastTraceRefreshTime = now
        }

        let activityElapsed = now - lastActivityRefreshTime
        if activityElapsed >= 0.25 || !snapshotIsLoading {
            refreshLiveActivitySnapshot(fresh: fresh)
            lastActivityRefreshTime = now
        }

        // #region agent log
        let storeCount = chatStore.conversation(for: conversationId)?.messages.count ?? -1
        let snapCount = messagesConversationSnapshot?.messages.count ?? -1
        let snapNil = messagesConversationSnapshot == nil
        if snapNil, storeCount > 0 {
            AgentDebugSessionNDJSONLog.appendThrottled(
                gateKey: "H1-snapshot-nil",
                hypothesisId: "H1",
                location: "refreshMessagesSnapshot",
                message: "snapshot_nil_but_store_has_messages",
                data: [
                    "conversationId": conversationId?.uuidString ?? "nil",
                    "storeCount": "\(storeCount)",
                    "snapshotIsLoading": "\(snapshotIsLoading)",
                ]
            )
        }
        if !snapNil, snapCount == 0, storeCount > 0 {
            AgentDebugSessionNDJSONLog.appendThrottled(
                gateKey: "H4-snapshot-empty",
                hypothesisId: "H4",
                location: "refreshMessagesSnapshot",
                message: "snapshot_empty_but_store_has_messages",
                data: [
                    "conversationId": conversationId?.uuidString ?? "nil",
                    "storeCount": "\(storeCount)",
                ]
            )
        }
        if let cid = conversationId, let snap = messagesConversationSnapshot, snap.id != cid {
            AgentDebugSessionNDJSONLog.appendThrottled(
                gateKey: "H14-snap-misaligned",
                minInterval: 0.15,
                hypothesisId: "H14",
                location: "refreshMessagesSnapshot",
                message: "snapshot_id_ne_conversationId",
                data: [
                    "selectedConversation": cid.uuidString,
                    "snapshotConversation": snap.id.uuidString,
                    "streamContentVersion": "\(streaming.streamContentVersion)",
                ]
            )
        }
        let renderBranch: String = {
            if messagesConversationSnapshot != nil { return "snapshot" }
            if let cid = conversationId, chatStore.conversation(for: cid) != nil { return "store_fallback" }
            return "placeholder"
        }()
        AgentDebugSessionNDJSONLog.appendThrottled(
            gateKey: "H13-render-branch",
            minInterval: 0.08,
            hypothesisId: "H13",
            location: "refreshMessagesSnapshot",
            message: "render_branch_after_refresh",
            data: [
                "branch": renderBranch,
                "conversationId": conversationId?.uuidString ?? "nil",
                "streamContentVersion": "\(streaming.streamContentVersion)",
                "snapMsgCount": "\(messagesConversationSnapshot?.messages.count ?? -1)",
            ]
        )
        // #endregion
    }

    /// Refresh trace events snapshot. Separated from main refresh
    /// so it can be throttled independently.
    private func refreshTraceEventsSnapshot(fresh: Conversation?) {
        guard let convId = conversationId ?? fresh?.id else { return }
        var newTraceMap: [UUID: [ToolTraceEvent]] = [:]
        for msg in (fresh?.messages ?? []) where msg.role == .assistant {
            newTraceMap[msg.id] = toolTraceStore.events(
                conversationId: convId,
                assistantMessageId: msg.id
            )
        }
        let countsChanged = newTraceMap.contains { key, events in
            snapshotTraceEvents[key]?.count != events.count
        } || newTraceMap.count != snapshotTraceEvents.count
        if countsChanged {
            snapshotTraceEvents = newTraceMap
        }
    }

    private func refreshLiveActivitySnapshot(fresh: Conversation?) {
        guard snapshotIsLoading, let convId = conversationId ?? fresh?.id else {
            snapshotActiveAssistantMessageId = nil
            snapshotStreamingStatusText = ""
            snapshotStreamingDetailText = nil
            snapshotInlineActivities = []
            snapshotSupervisorActivities = []
            snapshotLiveSubagentCards = []
            return
        }

        guard let activeAssistant = fresh?.messages.last(where: { $0.role == .assistant }) else {
            snapshotActiveAssistantMessageId = nil
            snapshotStreamingStatusText = ""
            snapshotStreamingDetailText = nil
            snapshotInlineActivities = []
            snapshotSupervisorActivities = []
            snapshotLiveSubagentCards = []
            return
        }

        let scoped = scopedTaskActivities(for: convId)
        let status = TaskActivityStore.streamingStatusText(
            isPaused: executionController.runState == .paused,
            activities: scoped
        )
        let detail: String? = {
            if isReasoningSuppressedForProvider(resolvedTurnProviderId(for: convId)) {
                return nil
            }
            if let assistantUpdate = TaskActivityStore.assistantUpdateText(in: scoped),
               let line = ChatStore.sanitizedStreamingDetailLine(assistantUpdate) {
                return line
            }
            if let fromActivities = TaskActivityStore.streamingDetailText(
                activities: scoped,
                activeOperationsCount: scopedActiveOperationsCount(for: convId)
            ), let line = ChatStore.sanitizedStreamingDetailLine(fromActivities) {
                return line
            }
            if let fromContent = ChatStore.extractLastOperationalThinkingLine(from: activeAssistant.content),
               let line = ChatStore.sanitizedStreamingDetailLine(fromContent) {
                return line
            }
            if let codexLine = streaming.codexLastReasoningLine, !codexLine.isEmpty, convId == self.conversationId,
               let line = ChatStore.sanitizedStreamingDetailLine(codexLine) {
                return line
            }
            if convId == streaming.streamingReasoningConversationId,
               let reasoning = streaming.streamingReasoningText,
               !reasoning.isEmpty {
                let lastLine = reasoning.split(separator: "\n", omittingEmptySubsequences: false)
                    .last?
                    .trimmingCharacters(in: CharacterSet.whitespaces) ?? ""
                if !lastLine.isEmpty, let line = ChatStore.sanitizedStreamingDetailLine(lastLine, ellipsis: "…") {
                    return line
                }
            }
            return nil
        }()

        let inlineActivities = scoped.filter { activity in
            guard TaskActivityStore.isConcreteVisibleEvent(activity) else { return false }
            if SwarmMetadata.isSupervisorEvent(activity.payload) { return false }
            if SwarmMetadata.isSwarmEvent(activity.payload)
                || activity.type == "agent"
                || activity.type == "subagent_text"
                || activity.type == "subagent_batch_done"
            {
                return false
            }
            if activity.type == "todo_write" || activity.type == "todo_read" {
                return false
            }
            return shouldShowOperationEventInLinearChat(
                eventType: activity.type,
                payload: activity.payload,
                showTodoCard: false
            )
        }

        let supervisorActivities = scoped.filter { activity in
            guard TaskActivityStore.isConcreteVisibleEvent(activity) else { return false }
            guard SwarmMetadata.isSupervisorEvent(activity.payload) else { return false }
            if activity.type == "todo_write" || activity.type == "todo_read" {
                return false
            }
            return true
        }

        let liveCards = visibleSwarmCardsForChat(
            from: taskActivityStore.swarmCardStates(for: convId)
        )

        snapshotActiveAssistantMessageId = activeAssistant.id
        snapshotStreamingStatusText = status
        snapshotStreamingDetailText = detail
        snapshotInlineActivities = inlineActivities
        snapshotSupervisorActivities = supervisorActivities
        snapshotLiveSubagentCards = liveCards
    }
}
