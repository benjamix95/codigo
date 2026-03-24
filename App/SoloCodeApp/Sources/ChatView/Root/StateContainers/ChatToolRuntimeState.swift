import Foundation
import SwiftUI

// MARK: - ChatToolRuntimeState

/// Groups tool-trace, policy-ack, and run-task tracking @State properties.
struct ChatToolRuntimeState {

    // MARK: - Tool Trace

    var activeToolTraceTurnsByConversation: [UUID: ToolTraceTurnContext] = [:]
    var toolTraceNextSequenceByMessage: [UUID: Int] = [:]
    var toolTraceOperationalSeenByMessage: [UUID: Bool] = [:]
    var toolTraceOperationalCountByMessage: [UUID: Int] = [:]
    var toolRuntimeSyncTask: Task<Void, Never>?

    // MARK: - Policy Ack

    var policyAckStateByMessage: [UUID: PolicyAckState] = [:]
    var toolStartRequirementsStateByMessage: [UUID: ToolStartRequirementsState] = [:]
    var policyAckFailedMessages: Set<UUID> = []
    var policyAckBlockedQueue: [UUID: [(
        type: String,
        payload: [String: String],
        providerId: String,
        conversationId: UUID?,
        shouldApplyPipelineArtifacts: Bool
    )]] = [:]

    // MARK: - Run Tasks

    var activeRunTaskByConversation: [UUID: Task<Void, Never>] = [:]
    var activeRunTokenByConversation: [UUID: UUID] = [:]
}
