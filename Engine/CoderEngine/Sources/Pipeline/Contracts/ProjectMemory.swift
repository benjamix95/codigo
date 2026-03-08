import Foundation

// MARK: - FileBugRecord

/// Storico bug per file, usato nel risk scoring (§6.6).
public struct FileBugRecord: Codable, Sendable, Equatable {
    public var bugCount: Int
    public var lastBug: String?

    public init(bugCount: Int = 0, lastBug: String? = nil) {
        self.bugCount = bugCount
        self.lastBug = lastBug
    }

    enum CodingKeys: String, CodingKey {
        case bugCount = "bug_count"
        case lastBug = "last_bug"
    }
}

// MARK: - ProjectMemory

/// Contratto dati della project memory (§6.6).
/// Persiste conoscenza accumulata sul progetto tra esecuzioni.
public struct ProjectMemory: Codable, Sendable, Equatable {
    public var workspace: String
    public var codingStandards: [String]
    public var namingRules: [String]
    public var forbiddenPatterns: [String]
    public var architectureNotes: [String]
    public var fileBugHistory: [String: FileBugRecord]
    public var lastUpdatedAt: Date

    public init(
        workspace: String,
        codingStandards: [String] = [],
        namingRules: [String] = [],
        forbiddenPatterns: [String] = [],
        architectureNotes: [String] = [],
        fileBugHistory: [String: FileBugRecord] = [:],
        lastUpdatedAt: Date = Date()
    ) {
        self.workspace = workspace
        self.codingStandards = codingStandards
        self.namingRules = namingRules
        self.forbiddenPatterns = forbiddenPatterns
        self.architectureNotes = architectureNotes
        self.fileBugHistory = fileBugHistory
        self.lastUpdatedAt = lastUpdatedAt
    }

    enum CodingKeys: String, CodingKey {
        case workspace
        case codingStandards = "coding_standards"
        case namingRules = "naming_rules"
        case forbiddenPatterns = "forbidden_patterns"
        case architectureNotes = "architecture_notes"
        case fileBugHistory = "file_bug_history"
        case lastUpdatedAt = "last_updated_at"
    }

    /// Score storico bug per un file (normalizzato 0..1).
    public func bugHistoryScore(for file: String) -> Double {
        guard let record = fileBugHistory[file] else { return 0 }
        return min(Double(record.bugCount) / 5.0, 1.0)
    }
}

extension ProjectMemory: PipelineValidatable {
    public func validate() throws {
        try PipelineValidationHelpers.requireNonEmpty(
            workspace, field: "workspace", contract: "ProjectMemory"
        )
    }
}
