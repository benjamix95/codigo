import Foundation
import CoderEngine

enum RustMainChatStoreAdapter {
    @MainActor
    static func taskRuntimeState(from store: ChatStore) -> MainChatTaskRuntimeStateBridge {
        MainChatTaskRuntimeStateBridge(
            taskStates: store.activeTaskConversationIds.map { conversationId in
                MainChatTaskStateSnapshotBridge(
                    conversationId: conversationId.uuidString.lowercased(),
                    startedAt: store.taskStartDates[conversationId],
                    statusText: store.taskStatusTexts[conversationId] ?? "Thinking"
                )
            }
        )
    }

    @MainActor
    static func apply(taskRuntimeState: MainChatTaskRuntimeStateBridge, to store: ChatStore) {
        let ordered = taskRuntimeState.taskStates.compactMap { snapshot -> (UUID, Date?, String)? in
            guard let uuid = UUID(uuidString: snapshot.conversationId) else { return nil }
            return (uuid, snapshot.startedAt, snapshot.statusText)
        }
        store.activeTaskConversationIds = Set(ordered.map(\.0))
        store.taskStartDates = Dictionary(uniqueKeysWithValues: ordered.map { ($0.0, $0.1) }.compactMap {
            guard let startedAt = $0.1 else { return nil }
            return ($0.0, startedAt)
        })
        store.taskStatusTexts = Dictionary(uniqueKeysWithValues: ordered.map { ($0.0, $0.2) })
    }

    @MainActor
    static func snapshot(from store: ChatStore) -> MainChatStoreSnapshotBridge {
        MainChatStoreSnapshotBridge(
            conversations: store.conversations.map(conversationSnapshot),
            planBoards: Dictionary(uniqueKeysWithValues: store.planBoards.map {
                ($0.key.uuidString.lowercased(), planBoardSnapshot($0.value))
            })
        )
    }

    @MainActor
    static func apply(snapshot: MainChatStoreSnapshotBridge, to store: ChatStore) {
        store.conversations = snapshot.conversations.compactMap(conversation)
        store.planBoards = Dictionary(uniqueKeysWithValues: snapshot.planBoards.compactMap { key, value in
            guard let uuid = UUID(uuidString: key) else { return nil }
            return (uuid, planBoard(value))
        })
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
        runtimeSnapshot: MainChatRuntimeSnapshotBridge?,
        selectedConversationId: UUID?,
        draftText: String,
        planPanelVisible: Bool,
        followLive: Bool,
        collapsedArtifactsByTurn: [String: Set<String>]
    ) -> MainChatUIStateBridge {
        MainChatUIStateBridge(
            storeSnapshot: snapshot(from: store),
            runtimeSnapshot: runtimeSnapshot,
            taskRuntimeState: taskRuntimeState(from: store),
            selectedConversationId: selectedConversationId?.uuidString.lowercased(),
            draftText: draftText,
            planPanelVisible: planPanelVisible,
            followLive: followLive,
            collapsedArtifactIdsByTurn: Dictionary(uniqueKeysWithValues: collapsedArtifactsByTurn.map {
                ($0.key, Array($0.value).sorted())
            })
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
        to store: ChatStore
    ) -> MainChatUIIntentResponseBridge? {
        guard let response = handleUIIntent(request) else { return nil }
        if let state = response.state {
            apply(snapshot: state.storeSnapshot, to: store)
            apply(taskRuntimeState: state.taskRuntimeState ?? .init(taskStates: []), to: store)
        }
        return response
    }

    static func conversationSnapshot(_ conversation: Conversation) -> MainChatStoreConversationSnapshotBridge {
        MainChatStoreConversationSnapshotBridge(
            id: conversation.id.uuidString.lowercased(),
            threadRootConversationId: conversation.threadRootConversationId.uuidString.lowercased(),
            title: conversation.title,
            messages: conversation.messages.map(messageSnapshot),
            createdAt: conversation.createdAt,
            contextId: conversation.contextId?.uuidString.lowercased(),
            contextFolderPath: conversation.contextFolderPath,
            mode: conversation.mode?.rawValue,
            preferredProviderId: conversation.preferredProviderId,
            contextMemorySummaryMarkdown: conversation.contextMemorySummaryMarkdown,
            contextMemoryGeneratedAt: conversation.contextMemoryGeneratedAt,
            contextMemorySourceMessageCount: conversation.contextMemorySourceMessageCount,
            isArchived: conversation.isArchived,
            isPinned: conversation.isPinned,
            isFavorite: conversation.isFavorite,
            lastInputTokens: conversation.lastInputTokens,
            workspaceId: conversation.workspaceId?.uuidString.lowercased(),
            adHocFolderPaths: conversation.adHocFolderPaths,
            checkpoints: conversation.checkpoints.map(checkpointSnapshot)
        )
    }

    static func messageSnapshot(_ message: ChatMessage) -> MainChatStoreMessageSnapshotBridge {
        MainChatStoreMessageSnapshotBridge(
            id: message.id.uuidString.lowercased(),
            role: message.role.rawValue,
            content: message.content,
            primaryTextSnapshot: message.primaryTextSnapshot,
            blocks: message.blocks?.map(blockSnapshot),
            turnMetadata: message.turnMetadata.map(turnMetadataSnapshot),
            isStreaming: message.isStreaming,
            imagePaths: message.imagePaths,
            attachments: message.attachments?.map(attachmentSnapshot),
            planAttachment: message.planAttachment.map(planAttachmentSnapshot),
            reasoningText: message.reasoningText,
            subagentCards: message.subagentCards?.map(subagentCardSnapshot)
        )
    }

    private static func conversation(_ snapshot: MainChatStoreConversationSnapshotBridge) -> Conversation? {
        guard let id = UUID(uuidString: snapshot.id),
              let rootId = UUID(uuidString: snapshot.threadRootConversationId) else { return nil }
        return Conversation(
            id: id,
            threadRootConversationId: rootId,
            title: snapshot.title,
            messages: snapshot.messages.compactMap(message),
            createdAt: snapshot.createdAt ?? .now,
            contextId: snapshot.contextId.flatMap(UUID.init(uuidString:)),
            contextFolderPath: snapshot.contextFolderPath,
            mode: snapshot.mode.flatMap(CoderMode.init(rawValue:)),
            preferredProviderId: snapshot.preferredProviderId,
            contextMemorySummaryMarkdown: snapshot.contextMemorySummaryMarkdown,
            contextMemoryGeneratedAt: snapshot.contextMemoryGeneratedAt,
            contextMemorySourceMessageCount: snapshot.contextMemorySourceMessageCount,
            isArchived: snapshot.isArchived,
            isPinned: snapshot.isPinned,
            isFavorite: snapshot.isFavorite,
            lastInputTokens: snapshot.lastInputTokens,
            workspaceId: snapshot.workspaceId.flatMap(UUID.init(uuidString:)),
            adHocFolderPaths: snapshot.adHocFolderPaths,
            checkpoints: snapshot.checkpoints.compactMap(checkpoint)
        )
    }

    private static func message(_ snapshot: MainChatStoreMessageSnapshotBridge) -> ChatMessage? {
        guard let id = UUID(uuidString: snapshot.id),
              let role = ChatMessage.Role(rawValue: snapshot.role) else { return nil }
        var message = ChatMessage(
            id: id,
            role: role,
            content: snapshot.content,
            primaryTextSnapshot: snapshot.primaryTextSnapshot,
            blocks: snapshot.blocks?.map(block),
            turnMetadata: snapshot.turnMetadata.map(turnMetadata),
            isStreaming: snapshot.isStreaming,
            imagePaths: snapshot.imagePaths,
            attachments: snapshot.attachments?.compactMap(attachment),
            planAttachment: snapshot.planAttachment.flatMap(planAttachment)
        )
        message.reasoningText = snapshot.reasoningText
        message.subagentCards = nil
        return message
    }

    private static func blockSnapshot(_ block: PersistedChatTimelineBlock) -> MainChatStoreTimelineBlockSnapshotBridge {
        MainChatStoreTimelineBlockSnapshotBridge(id: block.id, kind: block.kind.rawValue, title: block.title, text: block.text, items: block.items, metadata: block.metadata, isCollapsible: block.isCollapsible, isCollapsedByDefault: block.isCollapsedByDefault)
    }
    private static func block(_ snapshot: MainChatStoreTimelineBlockSnapshotBridge) -> PersistedChatTimelineBlock {
        PersistedChatTimelineBlock(id: snapshot.id, kind: ChatTimelineBlockKind(rawValue: snapshot.kind) ?? .primaryText, title: snapshot.title, text: snapshot.text, items: snapshot.items, metadata: snapshot.metadata, isCollapsible: snapshot.isCollapsible, isCollapsedByDefault: snapshot.isCollapsedByDefault)
    }
    private static func turnMetadataSnapshot(_ metadata: ChatTurnMetadata) -> MainChatStoreTurnMetadataSnapshotBridge {
        MainChatStoreTurnMetadataSnapshotBridge(turnId: metadata.turnId, providerId: metadata.providerId, sequence: metadata.sequence, status: metadata.status, startedAt: metadata.startedAt, completedAt: metadata.completedAt, updatedAt: metadata.updatedAt, isStreaming: metadata.isStreaming)
    }
    private static func turnMetadata(_ snapshot: MainChatStoreTurnMetadataSnapshotBridge) -> ChatTurnMetadata {
        ChatTurnMetadata(turnId: snapshot.turnId, providerId: snapshot.providerId, sequence: snapshot.sequence, status: snapshot.status, startedAt: snapshot.startedAt, completedAt: snapshot.completedAt, updatedAt: snapshot.updatedAt, isStreaming: snapshot.isStreaming)
    }
    private static func attachmentSnapshot(_ attachment: ChatAttachment) -> MainChatStoreAttachmentSnapshotBridge {
        MainChatStoreAttachmentSnapshotBridge(id: attachment.id.uuidString.lowercased(), kind: attachment.kind.rawValue, originalName: attachment.originalName, mimeType: attachment.mimeType, localPath: attachment.localPath, sizeBytes: attachment.sizeBytes, createdAt: attachment.createdAt)
    }
    private static func attachment(_ snapshot: MainChatStoreAttachmentSnapshotBridge) -> ChatAttachment? {
        guard let id = UUID(uuidString: snapshot.id), let kind = ChatAttachmentKind(rawValue: snapshot.kind) else { return nil }
        return ChatAttachment(id: id, kind: kind, originalName: snapshot.originalName, mimeType: snapshot.mimeType, localPath: snapshot.localPath, sizeBytes: snapshot.sizeBytes, createdAt: snapshot.createdAt ?? .now)
    }
    private static func planAttachmentSnapshot(_ attachment: PlanAttachment) -> MainChatStorePlanAttachmentSnapshotBridge {
        MainChatStorePlanAttachmentSnapshotBridge(historyEntryId: attachment.historyEntryId.uuidString.lowercased(), layoutVersion: attachment.layoutVersion, showExpand: attachment.showExpand, snapshotTitle: attachment.snapshotTitle)
    }
    private static func planAttachment(_ snapshot: MainChatStorePlanAttachmentSnapshotBridge) -> PlanAttachment? {
        guard let id = UUID(uuidString: snapshot.historyEntryId) else { return nil }
        return PlanAttachment(historyEntryId: id, layoutVersion: snapshot.layoutVersion, showExpand: snapshot.showExpand, snapshotTitle: snapshot.snapshotTitle)
    }
    static func subagentCardSnapshot(_ card: SubagentCardSnapshot) -> MainChatStoreSubagentCardSnapshotBridge {
        MainChatStoreSubagentCardSnapshotBridge(swarmId: card.swarmId, status: card.status.rawValue, title: card.title, detail: card.detail, summary: card.summary, errorCount: card.errorCount, warningCount: card.warningCount, resultPreview: card.resultPreview)
    }
    static func checkpointSnapshot(_ checkpoint: ConversationCheckpoint) -> MainChatStoreCheckpointSnapshotBridge {
        MainChatStoreCheckpointSnapshotBridge(id: checkpoint.id.uuidString.lowercased(), createdAt: checkpoint.createdAt, messageCount: checkpoint.messageCount, planBoardSnapshot: checkpoint.planBoardSnapshot.map(planBoardSnapshot), linkedPlanConversationId: checkpoint.linkedPlanConversationId?.uuidString.lowercased(), linkedPlanBoardSnapshot: checkpoint.linkedPlanBoardSnapshot.map(planBoardSnapshot), gitStates: checkpoint.gitStates.map(gitStateSnapshot))
    }
    private static func checkpoint(_ snapshot: MainChatStoreCheckpointSnapshotBridge) -> ConversationCheckpoint? {
        guard let id = UUID(uuidString: snapshot.id) else { return nil }
        return ConversationCheckpoint(id: id, createdAt: snapshot.createdAt ?? .now, messageCount: snapshot.messageCount, planBoardSnapshot: snapshot.planBoardSnapshot.map(planBoard), linkedPlanConversationId: snapshot.linkedPlanConversationId.flatMap(UUID.init(uuidString:)), linkedPlanBoardSnapshot: snapshot.linkedPlanBoardSnapshot.map(planBoard), gitStates: snapshot.gitStates.map(gitState))
    }
    private static func gitStateSnapshot(_ state: ConversationCheckpointGitState) -> MainChatStoreCheckpointGitStateSnapshotBridge {
        MainChatStoreCheckpointGitStateSnapshotBridge(gitRootPath: state.gitRootPath, gitSnapshotRef: state.gitSnapshotRef)
    }
    private static func gitState(_ snapshot: MainChatStoreCheckpointGitStateSnapshotBridge) -> ConversationCheckpointGitState {
        ConversationCheckpointGitState(gitRootPath: snapshot.gitRootPath, gitSnapshotRef: snapshot.gitSnapshotRef)
    }
    static func planBoardSnapshot(_ board: PlanBoard) -> MainChatStorePlanBoardSnapshotBridge {
        MainChatStorePlanBoardSnapshotBridge(goal: board.goal, options: board.options.map { .init(id: $0.id, title: $0.title, fullText: $0.fullText) }, chosenPath: board.chosenPath, steps: board.steps.map(planStepSnapshot), updatedAt: board.updatedAt, walkthroughMarkdown: board.walkthroughMarkdown, walkthroughSummary: board.walkthroughSummary, walkthroughOutcome: board.walkthroughOutcome)
    }
    private static func planBoard(_ snapshot: MainChatStorePlanBoardSnapshotBridge) -> PlanBoard {
        PlanBoard(goal: snapshot.goal, options: snapshot.options.map { PlanOption(id: $0.id, title: $0.title, fullText: $0.fullText) }, chosenPath: snapshot.chosenPath, steps: snapshot.steps.map(planStep), updatedAt: snapshot.updatedAt ?? .now, walkthroughMarkdown: snapshot.walkthroughMarkdown, walkthroughSummary: snapshot.walkthroughSummary, walkthroughOutcome: snapshot.walkthroughOutcome)
    }
    private static func planStepSnapshot(_ step: PlanStep) -> MainChatStorePlanStepSnapshotBridge {
        MainChatStorePlanStepSnapshotBridge(id: step.id, title: step.title, description: step.description, targetFile: step.targetFile, status: step.status.rawValue, linkedFiles: step.linkedFiles, dependsOn: step.dependsOn, notes: step.notes, updatedAt: step.updatedAt)
    }
    private static func planStep(_ snapshot: MainChatStorePlanStepSnapshotBridge) -> PlanStep {
        PlanStep(id: snapshot.id, title: snapshot.title, description: snapshot.description, targetFile: snapshot.targetFile, status: PlanStepStatus(rawValue: snapshot.status) ?? .pending, linkedFiles: snapshot.linkedFiles, dependsOn: snapshot.dependsOn, notes: snapshot.notes, updatedAt: snapshot.updatedAt ?? .now)
    }
}
