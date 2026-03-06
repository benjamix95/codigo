import Foundation

/// Strategia di routing ruolo/stage per job debug.
public struct DebugRoleAndStageStrategy: Sendable {
    public init() {}

    public func nextRole(for task: TaskNode, job: PipelineJob) -> AgentRole? {
        guard job.jobKind == .debug else { return nil }

        if let preferredAgentRole = task.preferredAgentRole {
            return preferredAgentRole
        }

        if let debugStage = task.debugStage,
           let stageRole = debugStage.defaultAgentRole {
            return stageRole
        }

        switch task.executionStyle {
        case .multiAgentFlow:
            return task.contextEnriched ? .debugger : .explorer
        case .singleAgent, .mcpTool, .nativeCommand:
            return .debugger
        }
    }
}
