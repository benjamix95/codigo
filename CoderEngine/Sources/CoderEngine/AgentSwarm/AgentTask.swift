import Foundation

/// Task assigned to an agent in the orchestrator plan
public struct AgentTask: Codable, Sendable {
    public let role: AgentRole
    public let taskDescription: String
    public let order: Int

    public init(role: AgentRole, taskDescription: String, order: Int) {
        self.role = role
        self.taskDescription = taskDescription
        self.order = order
    }
}
