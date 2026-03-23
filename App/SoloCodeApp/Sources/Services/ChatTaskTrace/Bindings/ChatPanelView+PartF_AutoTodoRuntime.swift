import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    @MainActor
    internal func resolvedMainChatRuntimeSnapshot(
        preferPlanRuntime: Bool = false
    ) -> MainChatRuntimeSnapshotBridge? {
        if preferPlanRuntime {
            return flowCoordinator.planRuntimeSnapshotState()
                ?? flowCoordinator.directRuntimeSnapshotState()
        }
        return flowCoordinator.directRuntimeSnapshotState()
            ?? flowCoordinator.planRuntimeSnapshotState()
    }

    @MainActor
    internal func currentMainChatUIState(
        conversationId targetConversationId: UUID?,
        runtimeSnapshot: MainChatRuntimeSnapshotBridge? = nil,
        preferPlanRuntime: Bool = false,
        includeAutoTodoRuntimeState: Bool = false
    ) -> MainChatUIStateBridge {
        RustMainChatStoreAdapter.uiState(
            from: chatStore,
            runtimeSnapshot: runtimeSnapshot
                ?? resolvedMainChatRuntimeSnapshot(preferPlanRuntime: preferPlanRuntime),
            selectedConversationId: targetConversationId ?? conversationId,
            draftText: inputText,
            planPanelVisible: showPlanPanel,
            followLive: isFollowingLive,
            collapsedArtifactsByTurn: collapsedArtifactsByTurn,
            autoTodoRuntimeStateByMessage: includeAutoTodoRuntimeState
                ? autoTodoRuntimeStateByMessage
                : [:]
        )
    }

    @MainActor
    @discardableResult
    internal func applyMainChatUIIntentBridge(
        _ intent: String,
        conversationId targetConversationId: UUID?,
        providerId: String? = nil,
        runtimeSnapshot: MainChatRuntimeSnapshotBridge? = nil,
        preferPlanRuntime: Bool = false,
        turnId: String? = nil,
        artifactId: String? = nil,
        text: String? = nil,
        timestamp: Date? = Date(),
        payload: [String: String] = [:],
        includeAutoTodoRuntimeState: Bool = false,
        preserveLocalMessages: Bool = false
    ) -> MainChatUIIntentResponseBridge? {
        let mergedPayload = (providerId.map { ["provider_id": $0] } ?? [:]).merging(payload) {
            _, new in new
        }
        let request = MainChatUIIntentRequestBridge(
            schemaVersion: 1,
            intent: intent,
            state: currentMainChatUIState(
                conversationId: targetConversationId,
                runtimeSnapshot: runtimeSnapshot,
                preferPlanRuntime: preferPlanRuntime,
                includeAutoTodoRuntimeState: includeAutoTodoRuntimeState
            ),
            conversationId: (targetConversationId ?? conversationId)?.uuidString.lowercased(),
            turnId: turnId,
            artifactId: artifactId,
            text: text,
            timestamp: timestamp,
            payload: mergedPayload
        )
        return RustMainChatStoreAdapter.applyUIIntent(
            request,
            to: chatStore,
            preserveLocalMessages: preserveLocalMessages
        )
    }

    @MainActor
    internal func projectMainChatUISnapshot(
        conversationId targetConversationId: UUID?,
        runtimeSnapshot: MainChatRuntimeSnapshotBridge? = nil,
        preferPlanRuntime: Bool = false,
        includeAutoTodoRuntimeState: Bool = false
    ) -> (snapshot: MainChatUISnapshotBridge, state: MainChatUIStateBridge)? {
        let state = currentMainChatUIState(
            conversationId: targetConversationId,
            runtimeSnapshot: runtimeSnapshot,
            preferPlanRuntime: preferPlanRuntime,
            includeAutoTodoRuntimeState: includeAutoTodoRuntimeState
        )
        guard let snapshot = RustMainChatStoreAdapter.projectUI(state) else { return nil }
        return (snapshot, state)
    }

    @MainActor
    internal func startAutoTodoIfNeeded(
        activity: TaskActivity,
        providerId: String,
        conversationId: UUID?
    ) {
        guard shouldTrackAutoTodo(for: activity, conversationId: conversationId) else { return }
        guard let turn = resolveToolTraceTurn(conversationId: conversationId, providerId: providerId) else {
            return
        }
        guard autoTodoRuntimeStateByMessage[turn.assistantMessageId.uuidString.lowercased()] == nil else {
            return
        }
        guard !didReceiveExplicitTodoByMessage.contains(turn.assistantMessageId) else { return }
        applyAutoTodoRuntimeIntent(
            "auto_todo_begin_runtime",
            assistantMessageId: turn.assistantMessageId,
            providerId: providerId,
            conversationId: turn.conversationId,
            activity: activity
        )
    }

    @MainActor
    internal func startAutoTodoPlaceholderIfNeeded(
        providerId: String,
        conversationId: UUID?
    ) {
        guard !isPlanBuildContext(
            conversationId: conversationId,
            phase: planFlowPhase,
            activeBuildPlanConversationId: activeBuildPlanConversationId,
            activeBuildAgentConversationId: activeBuildAgentConversationId
        ) else {
            return
        }
        guard let turn = resolveToolTraceTurn(conversationId: conversationId, providerId: providerId) else {
            return
        }
        guard autoTodoRuntimeStateByMessage[turn.assistantMessageId.uuidString.lowercased()] == nil else {
            return
        }
        guard !didReceiveExplicitTodoByMessage.contains(turn.assistantMessageId) else { return }
        applyAutoTodoRuntimeIntent(
            "auto_todo_begin_runtime",
            assistantMessageId: turn.assistantMessageId,
            providerId: providerId,
            conversationId: turn.conversationId
        )
    }

    @MainActor
    internal func refreshAutoTodoIfNeeded(
        activity: TaskActivity,
        providerId: String,
        conversationId: UUID?
    ) {
        guard shouldTrackAutoTodo(for: activity, conversationId: conversationId) else { return }
        guard let turn = resolveToolTraceTurn(conversationId: conversationId, providerId: providerId) else {
            return
        }
        guard !didReceiveExplicitTodoByMessage.contains(turn.assistantMessageId) else { return }
        applyAutoTodoRuntimeIntent(
            "auto_todo_record_operation",
            assistantMessageId: turn.assistantMessageId,
            providerId: providerId,
            conversationId: turn.conversationId,
            activity: activity
        )
    }

    @MainActor
    internal func applyAutoTodoRuntimeIntent(
        _ intent: String,
        assistantMessageId: UUID,
        providerId: String,
        conversationId: UUID,
        activity: TaskActivity? = nil,
        outcome: ToolTraceTurnOutcome? = nil
    ) {
        var payload: [String: String] = [
            "assistant_message_id": assistantMessageId.uuidString.lowercased(),
            "provider_id": providerId,
            "conversation_id": conversationId.uuidString.lowercased(),
        ]
        if let activity {
            payload["activity_title"] = activity.title
            payload["immediate_label"] = Self.immediateSubtitleLabel(for: activity)
            for key in ["path", "file", "files", "query", "command"] {
                if let value = activity.payload[key], !value.isEmpty {
                    payload[key] = value
                }
            }
        }
        if let outcome {
            payload["outcome"] = autoTodoOutcomeString(outcome)
        }

        guard let response = applyMainChatUIIntentBridge(
            intent,
            conversationId: conversationId,
            providerId: providerId,
            text: nil,
            timestamp: activity?.timestamp ?? Date(),
            payload: payload,
            includeAutoTodoRuntimeState: true
        ) else { return }
        autoTodoRuntimeStateByMessage = response.state?.autoTodoRuntimeStateByMessage
            ?? autoTodoRuntimeStateByMessage
        MainChatTodoPatchAdapter.apply(response.todoPatches, to: todoStore) { patch, conversationId, status, linkedFiles in
            guard let todoId = patch.todoId.flatMap(UUID.init(uuidString:)),
                  let title = patch.title,
                  let providerId = patch.providerId
            else {
                return
            }
            emitAutoTodoTraceUpdate(
                todoId: todoId,
                title: title,
                status: status,
                notes: patch.notes ?? "",
                linkedFiles: linkedFiles,
                providerId: providerId,
                conversationId: conversationId,
                timestamp: patch.timestamp ?? .now
            )
        }
    }

    internal func shouldTrackAutoTodo(
        for activity: TaskActivity,
        conversationId: UUID?
    ) -> Bool {
        if isPlanBuildContext(
            conversationId: conversationId,
            phase: planFlowPhase,
            activeBuildPlanConversationId: activeBuildPlanConversationId,
            activeBuildAgentConversationId: activeBuildAgentConversationId
        ) {
            return false
        }
        return isOperationalTraceActivity(activity)
    }

    private func autoTodoOutcomeString(_ outcome: ToolTraceTurnOutcome) -> String {
        switch outcome {
        case .success:
            return "success"
        case .failed:
            return "failed"
        case .aborted:
            return "aborted"
        }
    }
}
