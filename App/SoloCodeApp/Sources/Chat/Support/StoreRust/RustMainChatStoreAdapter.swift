import Foundation
import CoderEngine

enum RustMainChatStoreAdapter {
    @MainActor
    static func taskRuntimeState(from store: ChatStore) -> MainChatTaskRuntimeStateBridge {
        MainChatTaskRuntimeStateBridge(
            taskStates: store.activeTaskConversationIds.map { conversationId in
                MainChatTaskStateSnapshotBridge(
                    conversationId: conversationId.lowercasedString,
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
                ($0.key.lowercasedString, planBoardSnapshot($0.value))
            })
        )
    }

    @MainActor
    static func apply(
        snapshot: MainChatStoreSnapshotBridge,
        to store: ChatStore,
        preserveLocalMessages: Bool = false
    ) {
        let newConversations = snapshot.conversations.compactMap(conversation)
        if preserveLocalMessages {
            let existingStreamingIds = Set(
                store.conversations
                    .filter { conv in conv.messages.contains { $0.isStreaming } }
                    .map(\.id)
            )
            var merged = newConversations
            for existingConv in store.conversations where existingStreamingIds.contains(existingConv.id) {
                if let idx = merged.firstIndex(where: { $0.id == existingConv.id }) {
                    let existingStreamingMessages = existingConv.messages.filter(\.isStreaming)
                    for msg in existingStreamingMessages {
                        if !merged[idx].messages.contains(where: { $0.id == msg.id }) {
                            merged[idx].messages.append(msg)
                        }
                    }
                }
            }
            store.conversations = merged
        } else {
            store.conversations = newConversations
        }
        store.planBoards = Dictionary(uniqueKeysWithValues: snapshot.planBoards.compactMap { key, value in
            guard let uuid = UUID(uuidString: key) else { return nil }
            return (uuid, planBoard(value))
        })
    }

    static func conversationSnapshot(_ conversation: Conversation) -> MainChatStoreConversationSnapshotBridge {
        MainChatStoreConversationSnapshotBridge(
            id: conversation.id.lowercasedString,
            threadRootConversationId: conversation.threadRootConversationId.lowercasedString,
            title: conversation.title,
            messages: conversation.messages.map(messageSnapshot),
            createdAt: conversation.createdAt,
            contextId: conversation.contextId?.lowercasedString,
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
            workspaceId: conversation.workspaceId?.lowercasedString,
            adHocFolderPaths: conversation.adHocFolderPaths,
            checkpoints: conversation.checkpoints.map(checkpointSnapshot)
        )
    }

    static func messageSnapshot(_ message: ChatMessage) -> MainChatStoreMessageSnapshotBridge {
        MainChatStoreMessageSnapshotBridge(
            id: message.id.lowercasedString,
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

    static func conversation(_ snapshot: MainChatStoreConversationSnapshotBridge) -> Conversation? {
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
        message.subagentCards = snapshot.subagentCards?.compactMap(subagentCard)
        return message
    }

    private static func blockSnapshot(_ block: PersistedChatTimelineBlock) -> MainChatStoreTimelineBlockSnapshotBridge {
        MainChatStoreTimelineBlockSnapshotBridge(id: block.id, kind: block.kind.rawValue, title: block.title, text: block.text, items: block.items, metadata: block.metadata, isCollapsible: block.isCollapsible, isCollapsedByDefault: block.isCollapsedByDefault, sequence: block.sequence)
    }
    private static func block(_ snapshot: MainChatStoreTimelineBlockSnapshotBridge) -> PersistedChatTimelineBlock {
        PersistedChatTimelineBlock(id: snapshot.id, kind: ChatTimelineBlockKind(rawValue: snapshot.kind) ?? .primaryText, title: snapshot.title, text: snapshot.text, items: snapshot.items, metadata: snapshot.metadata, isCollapsible: snapshot.isCollapsible, isCollapsedByDefault: snapshot.isCollapsedByDefault, sequence: snapshot.sequence ?? 0)
    }
    private static func turnMetadataSnapshot(_ metadata: ChatTurnMetadata) -> MainChatStoreTurnMetadataSnapshotBridge {
        MainChatStoreTurnMetadataSnapshotBridge(turnId: metadata.turnId, providerId: metadata.providerId, sequence: metadata.sequence, status: metadata.status, startedAt: metadata.startedAt, completedAt: metadata.completedAt, updatedAt: metadata.updatedAt, isStreaming: metadata.isStreaming)
    }
    private static func turnMetadata(_ snapshot: MainChatStoreTurnMetadataSnapshotBridge) -> ChatTurnMetadata {
        ChatTurnMetadata(turnId: snapshot.turnId, providerId: snapshot.providerId, sequence: snapshot.sequence, status: snapshot.status, startedAt: snapshot.startedAt, completedAt: snapshot.completedAt, updatedAt: snapshot.updatedAt, isStreaming: snapshot.isStreaming)
    }
    private static func attachmentSnapshot(_ attachment: ChatAttachment) -> MainChatStoreAttachmentSnapshotBridge {
        MainChatStoreAttachmentSnapshotBridge(id: attachment.id.lowercasedString, kind: attachment.kind.rawValue, originalName: attachment.originalName, mimeType: attachment.mimeType, localPath: attachment.localPath, sizeBytes: attachment.sizeBytes, createdAt: attachment.createdAt)
    }
    private static func attachment(_ snapshot: MainChatStoreAttachmentSnapshotBridge) -> ChatAttachment? {
        guard let id = UUID(uuidString: snapshot.id), let kind = ChatAttachmentKind(rawValue: snapshot.kind) else { return nil }
        return ChatAttachment(id: id, kind: kind, originalName: snapshot.originalName, mimeType: snapshot.mimeType, localPath: snapshot.localPath, sizeBytes: snapshot.sizeBytes, createdAt: snapshot.createdAt ?? .now)
    }
    private static func planAttachmentSnapshot(_ attachment: PlanAttachment) -> MainChatStorePlanAttachmentSnapshotBridge {
        MainChatStorePlanAttachmentSnapshotBridge(historyEntryId: attachment.historyEntryId.lowercasedString, layoutVersion: attachment.layoutVersion, showExpand: attachment.showExpand, snapshotTitle: attachment.snapshotTitle)
    }
    private static func planAttachment(_ snapshot: MainChatStorePlanAttachmentSnapshotBridge) -> PlanAttachment? {
        guard let id = UUID(uuidString: snapshot.historyEntryId) else { return nil }
        return PlanAttachment(historyEntryId: id, layoutVersion: snapshot.layoutVersion, showExpand: snapshot.showExpand, snapshotTitle: snapshot.snapshotTitle)
    }
    static func subagentCardSnapshot(_ card: SubagentCardSnapshot) -> MainChatStoreSubagentCardSnapshotBridge {
        MainChatStoreSubagentCardSnapshotBridge(
            swarmId: card.swarmId,
            status: card.status.rawValue,
            title: card.title,
            detail: card.detail,
            summary: card.summary,
            errorCount: card.errorCount,
            warningCount: card.warningCount,
            resultPreview: card.resultPreview,
            transcript: card.transcript?.map(subagentTranscriptEntrySnapshot)
        )
    }
    private static func subagentCard(_ snapshot: MainChatStoreSubagentCardSnapshotBridge) -> SubagentCardSnapshot? {
        guard let status = SwarmCardStatus(rawValue: snapshot.status) else { return nil }
        return SubagentCardSnapshot(
            swarmId: snapshot.swarmId,
            status: status,
            title: snapshot.title,
            detail: snapshot.detail,
            summary: snapshot.summary,
            errorCount: snapshot.errorCount,
            warningCount: snapshot.warningCount,
            resultPreview: snapshot.resultPreview,
            transcript: snapshot.transcript?.map(subagentTranscriptEntry)
        )
    }
    private static func subagentTranscriptEntrySnapshot(
        _ entry: SubagentTranscriptEntry
    ) -> MainChatStoreSubagentTranscriptEntryBridge {
        MainChatStoreSubagentTranscriptEntryBridge(
            id: entry.id,
            kind: entry.kind.rawValue,
            title: entry.title,
            detail: entry.detail,
            timestamp: entry.timestamp,
            isRunning: entry.isRunning
        )
    }
    private static func subagentTranscriptEntry(
        _ snapshot: MainChatStoreSubagentTranscriptEntryBridge
    ) -> SubagentTranscriptEntry {
        SubagentTranscriptEntry(
            id: snapshot.id,
            kind: SubagentTranscriptEntryKind(rawValue: snapshot.kind) ?? .activity,
            title: snapshot.title,
            detail: snapshot.detail,
            timestamp: snapshot.timestamp,
            isRunning: snapshot.isRunning
        )
    }
    static func checkpointSnapshot(_ checkpoint: ConversationCheckpoint) -> MainChatStoreCheckpointSnapshotBridge {
        MainChatStoreCheckpointSnapshotBridge(id: checkpoint.id.lowercasedString, createdAt: checkpoint.createdAt, messageCount: checkpoint.messageCount, planBoardSnapshot: checkpoint.planBoardSnapshot.map(planBoardSnapshot), linkedPlanConversationId: checkpoint.linkedPlanConversationId?.lowercasedString, linkedPlanBoardSnapshot: checkpoint.linkedPlanBoardSnapshot.map(planBoardSnapshot), gitStates: checkpoint.gitStates.map(gitStateSnapshot))
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
    static func planBoard(_ snapshot: MainChatStorePlanBoardSnapshotBridge) -> PlanBoard {
        PlanBoard(goal: snapshot.goal, options: snapshot.options.map { PlanOption(id: $0.id, title: $0.title, fullText: $0.fullText) }, chosenPath: snapshot.chosenPath, steps: snapshot.steps.map(planStep), updatedAt: snapshot.updatedAt ?? .now, walkthroughMarkdown: snapshot.walkthroughMarkdown, walkthroughSummary: snapshot.walkthroughSummary, walkthroughOutcome: snapshot.walkthroughOutcome)
    }
    private static func planStepSnapshot(_ step: PlanStep) -> MainChatStorePlanStepSnapshotBridge {
        MainChatStorePlanStepSnapshotBridge(id: step.id, title: step.title, description: step.description, targetFile: step.targetFile, status: step.status.rawValue, linkedFiles: step.linkedFiles, dependsOn: step.dependsOn, notes: step.notes, updatedAt: step.updatedAt)
    }
    private static func planStep(_ snapshot: MainChatStorePlanStepSnapshotBridge) -> PlanStep {
        PlanStep(id: snapshot.id, title: snapshot.title, description: snapshot.description, targetFile: snapshot.targetFile, status: PlanStepStatus(rawValue: snapshot.status) ?? .pending, linkedFiles: snapshot.linkedFiles, dependsOn: snapshot.dependsOn, notes: snapshot.notes, updatedAt: snapshot.updatedAt ?? .now)
    }
}
