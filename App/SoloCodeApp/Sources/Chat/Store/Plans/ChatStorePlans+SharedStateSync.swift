import Foundation
import CoderEngine

private enum PlanSharedSyncFormatters {
    static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

extension ChatStore {
    func resolvePlanConversationId(preferred conversationId: UUID?) -> UUID? {
        if let conversationId {
            return conversationId
        }
        if let preferredExisting = preferredPlanConversationIdForCanonicalSync() {
            return preferredExisting
        }
        if let activeTaskConversationId {
            return activeTaskConversationId
        }
        if let latestConversation = conversations.last?.id {
            return latestConversation
        }
        return nil
    }

    func persistPlanBoard(_ board: PlanBoard, for conversationId: UUID) {
        planBoards[conversationId] = board
        savePlanBoards()
        syncPlanBoardToSharedState(board, conversationId: conversationId)
    }
}

private extension ChatStore {
    func syncPlanBoardToSharedState(_ board: PlanBoard, conversationId: UUID) {
        let signature = planSnapshotSignature(board)
        if planSharedSyncSignatureByConversation[conversationId] == signature {
            return
        }

        let payloadSteps: [[String: Any]] = board.steps.map { step in
            [
                "id": step.id,
                "title": step.title,
                "description": step.description,
                "target_file": step.targetFile as Any,
                "status": step.status.rawValue,
                "linked_files": step.linkedFiles,
                "depends_on": step.dependsOn,
                "notes": step.notes,
                "updated_at": PlanSharedSyncFormatters.iso8601.string(from: step.updatedAt),
            ]
        }

        MCPSharedState.writePlanSnapshotFromIDE(
            conversationId: conversationId,
            goal: board.goal,
            chosenPath: board.chosenPath,
            steps: payloadSteps,
            walkthroughMarkdown: board.walkthroughMarkdown,
            summary: board.walkthroughSummary,
            outcome: board.walkthroughOutcome,
            maxHistoryPerConversation: 50
        )
        planSharedSyncSignatureByConversation[conversationId] = signature
    }

    func planSnapshotSignature(_ board: PlanBoard) -> String {
        let canonicalSteps = board.steps.map { step in
            let files = step.linkedFiles.sorted().joined(separator: ",")
            let dependencies = step.dependsOn.sorted().joined(separator: ",")
            return [
                step.id,
                step.title,
                step.description,
                step.targetFile ?? "",
                step.status.rawValue,
                files,
                dependencies,
                step.notes,
            ].map { $0.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0 }
             .joined(separator: "|")
        }.joined(separator: "||")

        return [
            board.goal,
            board.chosenPath ?? "",
            canonicalSteps,
            board.walkthroughMarkdown ?? "",
            board.walkthroughSummary ?? "",
            board.walkthroughOutcome ?? "",
        ].map { $0.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0 }
         .joined(separator: "###")
    }
}
