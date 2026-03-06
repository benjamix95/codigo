import Foundation

/// Strategia centralizzata per selezionare il ruolo agente da eseguire.
public struct TaskRoleSelectionStrategy: Sendable {
    public let debugStrategy: DebugRoleAndStageStrategy

    public init(
        debugStrategy: DebugRoleAndStageStrategy = DebugRoleAndStageStrategy()
    ) {
        self.debugStrategy = debugStrategy
    }

    public func nextRole(for task: TaskNode, job: PipelineJob) -> AgentRole {
        if let preferredAgentRole = task.preferredAgentRole {
            return preferredAgentRole
        }

        if let debugRole = debugStrategy.nextRole(for: task, job: job) {
            return debugRole
        }

        if !task.contextEnriched {
            return .explorer
        }

        return .coder
    }
}
