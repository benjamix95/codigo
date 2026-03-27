import Foundation
import CoderEngine

extension RustMainChatStoreAdapter {
    @MainActor
    static func scopedSnapshot(
        from store: ChatStore,
        conversationIds: Set<UUID>,
        planBoardConversationIds: Set<UUID> = []
    ) -> MainChatStoreSnapshotBridge {
        let conversations = conversationIds.compactMap { conversationId -> MainChatStoreConversationSnapshotBridge? in
            guard let index = store.conversationIndex(for: conversationId) else { return nil }
            return conversationSnapshot(store.conversations[index])
        }
        let planBoards = Dictionary(
            uniqueKeysWithValues: planBoardConversationIds.compactMap { conversationId -> (String, MainChatStorePlanBoardSnapshotBridge)? in
                guard let board = store.planBoards[conversationId] else { return nil }
                return (conversationId.lowercasedString, planBoardSnapshot(board))
            }
        )
        return MainChatStoreSnapshotBridge(
            conversations: conversations,
            planBoards: planBoards
        )
    }

    /// Scoped apply for pipeline events: updates only the active conversation
    /// instead of replacing the entire `store.conversations` array.
    @MainActor
    static func applyScopedForPipeline(
        snapshot: MainChatStoreSnapshotBridge,
        to store: ChatStore,
        conversationId: UUID
    ) {
        guard let updatedConversationSnapshot = snapshot.conversations.first(where: {
            UUID(uuidString: $0.id) == conversationId
        }), let updatedConversation = conversation(updatedConversationSnapshot) else {
            apply(snapshot: snapshot, to: store, preserveLocalMessages: false)
            return
        }

        store.upsertConversationFromScopedRustBridge(updatedConversation)

        for (key, value) in snapshot.planBoards {
            guard let uuid = UUID(uuidString: key) else { continue }
            store.planBoards[uuid] = planBoard(value)
        }
    }

    static func loadNormalizedSnapshot(
        _ snapshot: MainChatStoreSnapshotBridge
    ) -> MainChatStoreSnapshotBridge? {
        let response: MainChatStoreResponseBridge? = ReviewCoreBridge.call(
            functionName: "chat_core_store_load",
            request: snapshot
        )
        return response?.error == nil ? response?.snapshot : nil
    }

    static func handle(_ request: MainChatStoreActionRequestBridge) -> MainChatStoreSnapshotBridge? {
        let response: MainChatStoreResponseBridge? = ReviewCoreBridge.call(
            functionName: "chat_core_store_handle_action",
            request: request
        )
        return response?.error == nil ? response?.snapshot : nil
    }

    static func handleTaskRuntime(
        _ request: MainChatTaskRuntimeRequestBridge
    ) -> MainChatTaskRuntimeStateBridge? {
        let response: MainChatTaskRuntimeResponseBridge? = ReviewCoreBridge.call(
            functionName: "chat_core_task_runtime_handle_action",
            request: request
        )
        return response?.error == nil ? response?.state : nil
    }

    static func handleMarkers(_ request: MainChatMarkersRequestBridge) -> String? {
        let response: MainChatMarkersResponseBridge? = ReviewCoreBridge.call(
            functionName: "chat_core_markers_handle",
            request: request
        )
        return response?.error == nil ? response?.text : nil
    }

    @MainActor
    static func uiState(
        from store: ChatStore,
        context: MainChatUIBridgeContext
    ) -> MainChatUIStateBridge {
        makeUIState(
            storeSnapshot: snapshot(from: store),
            taskRuntimeState: taskRuntimeState(from: store),
            context: context
        )
    }

    @MainActor
    static func scopedPipelineUIState(
        from store: ChatStore,
        context: MainChatUIBridgeContext,
        conversationId: UUID,
        relatedPlanBoardConversationId: UUID? = nil,
        providedTaskRuntimeState: MainChatTaskRuntimeStateBridge? = nil
    ) -> MainChatUIStateBridge {
        var planBoardConversationIds = Set<UUID>()
        if let relatedPlanBoardConversationId {
            planBoardConversationIds.insert(relatedPlanBoardConversationId)
        }
        return makeUIState(
            storeSnapshot: scopedSnapshot(
                from: store,
                conversationIds: Set([conversationId]),
                planBoardConversationIds: planBoardConversationIds
            ),
            taskRuntimeState: providedTaskRuntimeState ?? taskRuntimeState(from: store),
            context: context
        )
    }

    @MainActor
    static func scopedPipelineUIState(
        storeSnapshot: MainChatStoreSnapshotBridge,
        context: MainChatUIBridgeContext,
        taskRuntimeState: MainChatTaskRuntimeStateBridge?
    ) -> MainChatUIStateBridge {
        makeUIState(
            storeSnapshot: storeSnapshot,
            taskRuntimeState: taskRuntimeState,
            context: context
        )
    }

    static func projectUI(_ state: MainChatUIStateBridge) -> MainChatUISnapshotBridge? {
        let response: MainChatUIProjectResponseBridge? = ReviewCoreBridge.call(
            functionName: "chat_core_ui_project",
            request: MainChatUIProjectRequestBridge(schemaVersion: 1, state: state)
        )
        return response?.error == nil ? response?.snapshot : nil
    }

    static func handleUIIntent(
        _ request: MainChatUIIntentRequestBridge
    ) -> MainChatUIIntentResponseBridge? {
        ReviewCoreBridge.call(functionName: "chat_core_ui_handle_intent", request: request)
    }

    @MainActor
    static func applyUIIntent(
        _ request: MainChatUIIntentRequestBridge,
        to store: ChatStore,
        preserveLocalMessages: Bool = true
    ) -> MainChatUIIntentResponseBridge? {
        RustMainChatAdapterSignpost.measureApplyUIIntent(intentLabel: request.intent) {
            guard let response = handleUIIntent(request) else { return nil }
            if let state = response.state {
                apply(
                    snapshot: state.storeSnapshot,
                    to: store,
                    preserveLocalMessages: preserveLocalMessages
                )
                apply(taskRuntimeState: state.taskRuntimeState ?? .init(taskStates: []), to: store)
            }
            return response
        }
    }

    @MainActor
    static func applyUIIntentScopedForPipeline(
        _ request: MainChatUIIntentRequestBridge,
        to store: ChatStore,
        conversationId: UUID
    ) -> MainChatUIIntentResponseBridge? {
        RustMainChatAdapterSignpost.measureApplyUIIntent(intentLabel: request.intent) {
            guard let response = handleUIIntent(request) else { return nil }
            if let state = response.state {
                applyScopedForPipeline(
                    snapshot: state.storeSnapshot,
                    to: store,
                    conversationId: conversationId
                )
                apply(taskRuntimeState: state.taskRuntimeState ?? .init(taskStates: []), to: store)
            }
            return response
        }
    }

    @MainActor
    static func applyPipelineEvent(
        _ event: ChatPipelineEvent,
        to store: ChatStore,
        context: MainChatUIBridgeContext,
        preserveLocalMessages: Bool = false
    ) -> MainChatUIIntentResponseBridge? {
        let request = MainChatUIIntentRequestBridge(
            intent: "pipeline_apply_event",
            state: scopedPipelineUIState(
                from: store,
                context: context,
                conversationId: event.conversationId
            ),
            conversationId: event.conversationId,
            turnId: event.turnId,
            artifactId: nil,
            text: nil,
            timestamp: event.timestamp,
            pipelineEvent: event,
            payload: [:]
        )
        return applyUIIntent(
            request,
            to: store,
            preserveLocalMessages: preserveLocalMessages
        )
    }

    @MainActor
    static func applyPipelineEvents(
        _ events: [ChatPipelineEvent],
        to store: ChatStore,
        context: MainChatUIBridgeContext,
        preserveLocalMessages: Bool = false
    ) -> MainChatUIIntentResponseBridge? {
        guard let first = events.first else { return nil }
        let request = MainChatUIIntentRequestBridge(
            intent: "pipeline_apply_events",
            state: scopedPipelineUIState(
                from: store,
                context: context,
                conversationId: first.conversationId
            ),
            conversationId: first.conversationId,
            turnId: first.turnId,
            artifactId: nil,
            text: nil,
            timestamp: events.last?.timestamp,
            pipelineEvent: nil,
            pipelineEvents: events,
            payload: [:]
        )
        return applyUIIntent(
            request,
            to: store,
            preserveLocalMessages: preserveLocalMessages
        )
    }

    @MainActor
    private static func makeUIState(
        storeSnapshot: MainChatStoreSnapshotBridge,
        taskRuntimeState: MainChatTaskRuntimeStateBridge?,
        context: MainChatUIBridgeContext
    ) -> MainChatUIStateBridge {
        MainChatUIStateBridge(
            storeSnapshot: storeSnapshot,
            runtimeSnapshot: context.runtimeSnapshot,
            taskRuntimeState: taskRuntimeState,
            selectedConversationId: context.selectedConversationId?.lowercasedString,
            draftText: context.draftText,
            planPanelVisible: context.planPanelVisible,
            followLive: context.followLive,
            collapsedArtifactIdsByTurn: Dictionary(uniqueKeysWithValues: context.collapsedArtifactsByTurn.map {
                ($0.key, Array($0.value).sorted())
            }),
            autoTodoRuntimeStateByMessage: context.autoTodoRuntimeStateByMessage
        )
    }
}
