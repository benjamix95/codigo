import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    /// Refresh conversation and loading snapshot from ObservableObjects.
    /// Called on every streamContentVersion change and messages.count change.
    internal func refreshMessagesSnapshot() {
        let fresh = chatStore.conversation(for: conversationId)

        // Always update loading state.
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

        // Only update conversation if actually different.
        let needsSnapshotUpdate =
            messagesConversationSnapshot?.id != fresh?.id
            || snapshotCount != freshCount
            || snapshotLastContent != freshLastContent
            || snapshotLastReasoning != freshLastReasoning
            || snapshotLastStreaming != freshLastStreaming
            || snapshotLastBlocks != freshLastBlocks

        if needsSnapshotUpdate {
            if let fresh {
                let prevSnapId = messagesConversationSnapshot?.id.uuidString ?? "nil"
                // Durante task/piano attivo, uno store Rust transitorio può restituire `messages` vuoti
                // per lo stesso thread: sostituire lo snapshot svuoterebbe la lista (“chat sparita”).
                let spuriousEmptyWhileBusy =
                    fresh.messages.isEmpty
                    && chromeBusy
                    && (messagesConversationSnapshot.map { $0.id == fresh.id && !$0.messages.isEmpty } ?? false)
                if spuriousEmptyWhileBusy {
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
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - lastTraceRefreshTime
        if elapsed >= 0.25 || !snapshotIsLoading {
            refreshTraceEventsSnapshot(fresh: fresh)
            lastTraceRefreshTime = now
        }

        // Sottotitolo live e planning: aggiornare sempre col messaggio (il throttle qui
        // causava lag vs overlay composer e detail "Planning next move" fuori sync).
        refreshLiveActivitySnapshot(fresh: fresh)

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
    }
}
