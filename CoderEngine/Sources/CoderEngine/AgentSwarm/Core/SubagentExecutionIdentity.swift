import Foundation

public struct SubagentExecutionIdentity: Sendable, Equatable {
    public let swarmId: String
    public let agentName: String
    public let taskSummary: String

    public init(
        swarmId: String,
        agentName: String,
        taskSummary: String
    ) {
        self.swarmId = swarmId
        self.agentName = agentName
        self.taskSummary = taskSummary
    }
}

public enum SubagentExecutionIdentityBuilder {
    public static func make(
        role: SubagentRole,
        task: String,
        collisionIndex: Int? = nil
    ) -> SubagentExecutionIdentity {
        let baseName = self.baseName(role: role, task: task)
        let agentName: String
        if let collisionIndex, collisionIndex > 1 {
            agentName = "\(baseName)-\(collisionIndex)"
        } else {
            agentName = baseName
        }

        return SubagentExecutionIdentity(
            swarmId: agentName,
            agentName: agentName,
            taskSummary: taskSummary(from: task)
        )
    }

    public static func baseName(role: SubagentRole, task: String) -> String {
        let label = deriveTaskLabel(from: task)
        let safeLabel = label.isEmpty ? role.displayName : label
        return "\(safeLabel)-\(role.rawValue)"
    }

    public static func deriveTaskLabel(from task: String) -> String {
        let cleaned = task
            .replacingOccurrences(of: #"`([^`]*)`"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\[[^\]]+\]\([^)]+\)"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[>*_#\-\+\[\]\(\)\{\}:]"#, with: " ", options: .regularExpression)
        let words = cleaned
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .prefix(6)
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
        return String(words.joined().prefix(30))
    }

    public static func taskSummary(from task: String, maxLength: Int = 120) -> String {
        let compact = task
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !compact.isEmpty else { return "" }
        return String(compact.prefix(maxLength))
    }
}
