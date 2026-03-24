import Foundation

public struct SubagentExecutionIdentity: Sendable, Equatable {
    public let swarmId: String
    public let agentName: String
    public let taskSummary: String
    /// Human-readable display name with spaces (e.g. "Auth Login Flow").
    public let readableName: String

    public init(
        swarmId: String,
        agentName: String,
        taskSummary: String,
        readableName: String = ""
    ) {
        self.swarmId = swarmId
        self.agentName = agentName
        self.taskSummary = taskSummary
        self.readableName = readableName.isEmpty ? agentName : readableName
    }
}

public enum SubagentExecutionIdentityBuilder {
    private static let fillerWords: Set<String> = [
        "a", "an", "and", "are", "as", "at", "be", "by", "da", "dei", "del", "della", "dello",
        "di", "e", "ed", "for", "from", "gli", "i", "il", "in", "into", "la", "le", "lo", "lato", "of",
        "on", "or", "per", "su", "that", "the", "this", "to", "with",
    ]

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
        let readable = readableDisplayName(from: task, role: role)

        return SubagentExecutionIdentity(
            swarmId: agentName,
            agentName: agentName,
            taskSummary: taskSummary(from: task),
            readableName: readable.isEmpty ? role.displayName : readable
        )
    }

    public static func baseName(role: SubagentRole, task: String) -> String {
        let label = deriveTaskLabel(from: task, role: role)
        guard !label.isEmpty else { return role.displayName }
        return "\(role.displayName)-\(label)"
    }

    /// Derives a human-readable display name from the task (space-separated words).
    public static func readableDisplayName(
        from task: String,
        role: SubagentRole? = nil
    ) -> String {
        let cleaned = task
            .replacingOccurrences(of: #"`([^`]*)`"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\[[^\]]+\]\([^)]+\)"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[>*_#\-\+\[\]\(\)\{\}:]"#, with: " ", options: .regularExpression)

        let roleSpecificNoise = leadingNoiseWords(for: role)
        let words = cleaned
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { word in
                let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return false }
                let lower = trimmed.lowercased()
                return !fillerWords.contains(lower) && !roleSpecificNoise.contains(lower)
            }
            .prefix(5)
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
        let joined = words.joined(separator: " ")
        return String(joined.prefix(60))
    }

    public static func deriveTaskLabel(
        from task: String,
        role: SubagentRole? = nil
    ) -> String {
        let cleaned = task
            .replacingOccurrences(of: #"`([^`]*)`"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\[[^\]]+\]\([^)]+\)"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[>*_#\-\+\[\]\(\)\{\}:]"#, with: " ", options: .regularExpression)

        let roleSpecificNoise = leadingNoiseWords(for: role)
        let words = cleaned
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { word in
                let trimmed = word.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return false }
                let lower = trimmed.lowercased()
                return !fillerWords.contains(lower) && !roleSpecificNoise.contains(lower)
            }
            .prefix(8)
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
        return String(words.joined().prefix(48))
    }

    public static func taskSummary(from task: String, maxLength: Int = 500) -> String {
        let compact = task
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !compact.isEmpty else { return "" }
        return String(compact.prefix(maxLength))
    }

    private static func leadingNoiseWords(for role: SubagentRole?) -> Set<String> {
        switch role {
        case .explorer:
            return ["analyze", "analyse", "check", "esplora", "explore", "inspect", "investigate", "research", "review", "rivedi", "study", "verify", "verifica"]
        case .reviewer:
            return ["audit", "check", "inspect", "review", "rivedi", "scan", "verify", "verifica"]
        case .bugHunter:
            return ["analyze", "bug", "bugs", "check", "find", "hunt", "investigate", "regression", "review", "scan", "verify"]
        case .debugger:
            return ["debug", "diagnose", "fix", "indaga", "investigate", "repair", "resolve", "risolvi"]
        case .coder:
            return ["build", "code", "create", "implement", "write"]
        case .testWriter:
            return ["add", "create", "test", "tests", "verify", "write"]
        case .docWriter:
            return ["document", "docs", "write"]
        case .securityAuditor:
            return ["analyze", "audit", "review", "scan", "security", "verify"]
        case .none:
            return []
        }
    }
}
