import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    /// Refresh conversation and loading snapshot from ObservableObjects.
    /// Called on every streamContentVersion change and messages.count change.
    internal func refreshMessagesSnapshot() {
        let fresh = chatStore.conversation(for: conversationId)
        let now = Date()

        // Always update loading state.
        let wasLoadingForPostTaskGrace = snapshotIsLoading
        let freshLoading = chatStore.isTaskActive(for: conversationId)
            || pipelineIntegrationService.isRunning(for: conversationId)
        if snapshotIsLoading != freshLoading {
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
            snapshotIsLoading = freshLoading
        }
        // Ancorare la grace anti-store-vuoto al momento preciso in cui il task termina (non solo
        // all’ultimo tick mentre `chromeBusy` era true), così copriamo buchi lunghi come in debug `2fa5b8`.
        if wasLoadingForPostTaskGrace, !freshLoading {
            snapshotLastBusyAt = now
        }

        let planBuilding =
            planFlowPhase == .building && activeBuildPlanConversationId == conversationId
        let chromeBusy = freshLoading || planBuilding
        if chromeBusy {
            snapshotLastBusyAt = now
        }
        if snapshotChromeLoading != chromeBusy {
            snapshotChromeLoading = chromeBusy
        }

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
        // Streaming aggiorna spesso `primaryTextSnapshot` mentre `content` resta indietro fino al flush:
        // senza questo confronto `needsSnapshotUpdate` resta falso e la lista non rispecchia il testo live (log H11).
        let snapshotLastResolvedPrimary =
            messagesConversationSnapshot?.messages.last.map { $0.resolvedPrimaryText.count } ?? -1
        let freshLastResolvedPrimary = fresh?.messages.last.map { $0.resolvedPrimaryText.count } ?? -1
        let snapshotLastTimelinePayload = chatMessageTimelinePayloadCharSum(
            messagesConversationSnapshot?.messages.last
        )
        let freshLastTimelinePayload = chatMessageTimelinePayloadCharSum(fresh?.messages.last)

        // Only update conversation if actually different.
        let needsSnapshotUpdate =
            messagesConversationSnapshot?.id != fresh?.id
            || snapshotCount != freshCount
            || snapshotLastContent != freshLastContent
            || snapshotLastReasoning != freshLastReasoning
            || snapshotLastStreaming != freshLastStreaming
            || snapshotLastBlocks != freshLastBlocks
            || snapshotLastResolvedPrimary != freshLastResolvedPrimary
            || snapshotLastTimelinePayload != freshLastTimelinePayload

        if needsSnapshotUpdate {
            if let fresh {
                let prevSnapId = messagesConversationSnapshot?.id.uuidString ?? "nil"
                // Durante task/piano attivo, uno store Rust transitorio può restituire `messages` vuoti
                // per lo stesso thread: sostituire lo snapshot svuoterebbe la lista (“chat sparita”).
                // Manteniamo una breve grace window anche subito dopo la fine del task per coprire
                // publish/store updates che arrivano in ritardo rispetto al flip `isLoading=false`.
                let shouldPreserveTransientEmpty = shouldPreserveSnapshotAgainstTransientEmptyStore(
                    freshConversationId: fresh.id,
                    freshMessageCount: fresh.messages.count,
                    previousSnapshotConversationId: messagesConversationSnapshot?.id,
                    previousSnapshotMessageCount: messagesConversationSnapshot?.messages.count ?? 0,
                    chromeBusy: chromeBusy,
                    lastBusyAt: snapshotLastBusyAt,
                    now: now
                )
                if shouldPreserveTransientEmpty {
                    AgentDebugSessionNDJSONLog.appendThrottled(
                        gateKey: "H16-skip-spurious-empty",
                        minInterval: 0.09,
                        hypothesisId: "H16",
                        location: "refreshMessagesSnapshot",
                        message: "preserved_snapshot_spurious_empty_store",
                        data: [
                            "conversationId": conversationId?.uuidString ?? "nil",
                            "prevCount": "\(messagesConversationSnapshot?.messages.count ?? -1)",
                            "streamContentVersion": "\(streaming.streamContentVersion)",
                            "chromeBusy": "\(chromeBusy)",
                            "lastBusyAgeMs": snapshotLastBusyAt.map {
                                "\(Int(now.timeIntervalSince($0) * 1000))"
                            } ?? "nil",
                        ]
                    )
                } else {
                    messagesConversationSnapshot = fresh
                    AgentDebugSessionNDJSONLog.appendThrottled(
                        gateKey: "H8-snapshot-mutate",
                        minInterval: 0.06,
                        hypothesisId: "H8",
                        location: "refreshMessagesSnapshot",
                        message: "snapshot_state_replaced",
                        data: [
                            "conversationId": conversationId?.uuidString ?? "nil",
                            "prevSnapId": prevSnapId,
                            "freshId": fresh.id.uuidString,
                            "freshCount": "\(freshCount)",
                            "freshLastContentLen": "\(freshLastContent)",
                            "freshLastStreaming": "\(freshLastStreaming)",
                            "streamContentVersion": "\(streaming.streamContentVersion)",
                            "snapshotIsLoading": "\(snapshotIsLoading)",
                        ]
                    )
                }
            } else {
                // `conversation(for:)` può essere nil per un frame (coalescing store, binding,
                // ecc.): **non** assegnare mai `messagesConversationSnapshot = nil` in quel caso,
                // altrimenti `needsSnapshotUpdate` è vero (conteggi -1 vs N) e la lista svuota —
                // sfarfallio / “chat ferma” (regressione post-refactor refresh).
                if conversationId == nil {
                    messagesConversationSnapshot = nil
                } else if let snap = messagesConversationSnapshot, snap.id != conversationId {
                    messagesConversationSnapshot = nil
                } else {
                    AgentDebugSessionNDJSONLog.appendThrottled(
                        gateKey: "H15-preserve-snapshot-fresh-nil",
                        minInterval: 0.12,
                        hypothesisId: "H15",
                        location: "refreshMessagesSnapshot",
                        message: "preserved_snapshot_avoid_nil_fresh",
                        data: [
                            "conversationId": conversationId?.uuidString ?? "nil",
                            "snapshotMsgCount": "\(messagesConversationSnapshot?.messages.count ?? -1)",
                            "snapshotId": messagesConversationSnapshot?.id.uuidString ?? "nil",
                            "streamContentVersion": "\(streaming.streamContentVersion)",
                        ]
                    )
                }
            }
        } else if snapshotIsLoading || freshLoading {
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
                    "freshTimelinePayloadLen": "\(freshLastTimelinePayload)",
                    "snapshotIsLoading": "\(snapshotIsLoading)",
                    "freshLoading": "\(freshLoading)",
                ]
            )
        }

        // Throttle trace events refresh: only update at most every 250ms.
        // This prevents the barrier fingerprint from changing on every
        // streamContentVersion increment (215+ per session), which was
        // causing ~710 EQ-MISS. Text deltas are the most frequent
        // streamContentVersion source but don't affect trace events.
        let refreshNow = CFAbsoluteTimeGetCurrent()
        let elapsed = refreshNow - lastTraceRefreshTime
        if elapsed >= 0.25 || !snapshotIsLoading {
            refreshTraceEventsSnapshot(fresh: fresh)
            lastTraceRefreshTime = refreshNow
        }

        // Sottotitolo live e planning: aggiornare sempre col messaggio (il throttle qui
        // causava lag vs overlay composer e detail "Planning next move" fuori sync).
        refreshLiveActivitySnapshot(fresh: fresh)

        let storeCount = chatStore.conversation(for: conversationId)?.messages.count ?? -1
        let snapCount = messagesConversationSnapshot?.messages.count ?? -1
        let snapNil = messagesConversationSnapshot == nil

        // Safety net: se lo snapshot è allineato ma ha MENO messaggi dello store,
        // è un residuo di lettura willSet-stale. Correzione immediata per evitare
        // che il layout della ScrollView si blocchi su contenuto incompleto.
        if let cid = conversationId,
           let snap = messagesConversationSnapshot,
           snap.id == cid,
           storeCount > snapCount,
           let storeConv = chatStore.conversation(for: cid) {
            messagesConversationSnapshot = storeConv
            AgentDebugSessionNDJSONLog.appendThrottled(
                gateKey: "H20-willset-stale-correction",
                minInterval: 0.06,
                hypothesisId: "H20",
                location: "refreshMessagesSnapshot",
                message: "corrected_stale_willset_snapshot",
                data: [
                    "conversationId": cid.uuidString,
                    "snapCountBefore": "\(snapCount)",
                    "storeCount": "\(storeCount)",
                ]
            )
        }

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
        let listSource: String = {
            guard let cid = conversationId else { return "placeholder" }
            if let snap = messagesConversationSnapshot, snap.id == cid {
                return "aligned_snapshot"
            }
            if chatStore.conversation(for: cid) != nil { return "store" }
            return "placeholder"
        }()
        AgentDebugSessionNDJSONLog.appendThrottled(
            gateKey: "H13-render-branch",
            minInterval: 0.08,
            hypothesisId: "H13",
            location: "refreshMessagesSnapshot",
            message: "render_branch_after_refresh",
            data: [
                "listSource": listSource,
                "conversationId": conversationId?.uuidString ?? "nil",
                "streamContentVersion": "\(streaming.streamContentVersion)",
                "snapMsgCount": "\(messagesConversationSnapshot?.messages.count ?? -1)",
            ]
        )
        if let lastApplyAt = streaming.lastMainChatStreamApplyAt {
        }

        hydratePipelineTurnCacheFromPersistedAssistantMessagesIfNeeded()
    }
}

/// Lo stream può aggiornare solo `blocks[].text` (timeline) mentre `content` e `primaryTextSnapshot` restano fermi → H11 con `resolvedPrimaryText` piatta.
private func chatMessageTimelinePayloadCharSum(_ message: ChatMessage?) -> Int {
    guard let message else { return -1 }
    return message.resolvedTimelineBlocks.reduce(0) { partial, block in
        partial + block.text.count + block.items.reduce(0) { $0 + $1.count }
    }
}
