import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

func resolveTaskStatusConversationId(
    activityPayload: [String: String],
    fallbackConversationId: UUID?
) -> UUID? {
    if let scope = canonicalConversationScope(from: activityPayload),
       let parsedConversationId = UUID(uuidString: scope) {
        return parsedConversationId
    }
    return fallbackConversationId
}

func payloadWithConversationScope(
    payload: [String: String],
    conversationId: UUID?
) -> [String: String] {
    var updated = payload
    if let scopedConversationId = canonicalConversationScope(from: updated) {
        updated["conversation_id"] = scopedConversationId
        return updated
    }
    guard let conversationId else { return updated }
    if canonicalConversationScopeValue(updated["conversation_id"]) == nil {
        updated["conversation_id"] = conversationId.uuidString.lowercased()
    }
    return updated
}

extension ChatPanelView {
    internal func linkedContextPaths() -> [String] {
        var ordered: [String] = []
        ordered.append(contentsOf: todoStore.todos.flatMap(\.linkedFiles))
        if let board = chatStore.planBoard(for: conversationId) {
            ordered.append(contentsOf: board.steps.compactMap(\.targetFile))
        }
        var seen = Set<String>()
        let deduped = ordered.filter { seen.insert($0).inserted }
        guard let context = effectiveContext.context else { return deduped }
        return deduped.compactMap { ref in
            switch ContextPathResolver.resolve(reference: ref, context: context) {
            case .resolved(let path):
                return path
            case .ambiguous(let matches):
                return matches.first
            case .notFound:
                return nil
            }
        }
    }

    internal func openChangedFile(_ repoRelativePath: String) {
        guard let gitRoot = gitPanelStore.gitRoot else { return }
        let absolutePath = URL(fileURLWithPath: gitRoot).appendingPathComponent(repoRelativePath)
            .path
        let gitService = GitService()
        openFilesStore.openFileWithDiff(absolutePath, gitRoot: gitRoot, gitService: gitService)
        selectMode(.ide)
    }

    internal func streamingStatusText(for message: ChatMessage) -> String {
        guard message.isStreaming, message.role == .assistant else { return "" }
        let scopedActivities = scopedTaskActivities(for: conversationId)
        return TaskActivityStore.streamingStatusText(
            isPaused: executionController.runState == .paused,
            activities: scopedActivities
        )
    }

    internal func updateSidebarTaskStatus() {
        guard let currentConversationId = conversationId,
              chatStore.isTaskActive(for: currentConversationId) else { return }
        let scopedActivities = scopedTaskActivities(for: currentConversationId)
        let status = TaskActivityStore.streamingStatusText(
            isPaused: executionController.runState == .paused,
            activities: scopedActivities
        )
        chatStore.setTaskStatus(status, for: currentConversationId)
    }

    @MainActor
    internal func streamingDetailText(for message: ChatMessage, conversationId convId: UUID?) -> String? {
        guard message.isStreaming, message.role == .assistant else { return nil }
        let scopedActivities = scopedTaskActivities(for: convId)
        if let assistantUpdate = TaskActivityStore.assistantUpdateText(in: scopedActivities) {
            return assistantUpdate
        }
        if let fromActivities = TaskActivityStore.streamingDetailText(
            activities: scopedActivities,
            activeOperationsCount: scopedActiveOperationsCount(for: convId)
        ) {
            return fromActivities
        }
        if let fromContent = ChatStore.extractLastOperationalThinkingLine(from: message.content) {
            return fromContent
        }
        if let codexLine = streaming.codexLastReasoningLine, !codexLine.isEmpty, convId == self.conversationId {
            return codexLine.count > 80 ? String(codexLine.prefix(77)) + "..." : codexLine
        }
        if convId == streaming.streamingReasoningConversationId, let reasoning = streaming.streamingReasoningText, !reasoning.isEmpty {
            let lastLine = reasoning.split(separator: "\n", omittingEmptySubsequences: false)
                .last?
                .trimmingCharacters(in: CharacterSet.whitespaces) ?? ""
            if !lastLine.isEmpty {
                return lastLine.count > 80 ? String(lastLine.prefix(77)) + "…" : lastLine
            }
        }
        return nil
    }

    internal func scopedTaskActivities(for targetConversationId: UUID?) -> [TaskActivity] {
        guard let targetConversationId else { return taskActivityStore.activities }
        // Pre-compute the lowercased UUID once. Use caseInsensitiveCompare
        // instead of .lowercased() per activity to avoid allocating a new
        // String for every activity in the filter loop.
        let expected = targetConversationId.uuidString
        return taskActivityStore.activities.filter { activity in
            let raw = activity.payload["conversation_id"]
                ?? activity.payload["conversationId"]
                ?? ""
            return raw.caseInsensitiveCompare(expected) == .orderedSame
        }
    }

    internal func scopedActiveOperationsCount(for targetConversationId: UUID?) -> Int {
        let activities = scopedTaskActivities(for: targetConversationId)
        return activities.suffix(40)
            .filter { $0.isRunning && !SwarmMetadata.isSwarmEvent($0.payload) }
            .count
    }
}
