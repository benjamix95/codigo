import Foundation

// MARK: - CodeReviewFinding

/// Represents a single code review finding (issue, suggestion, or improvement).
public struct CodeReviewFinding: Sendable, Identifiable, Codable {
    public let id: String
    public let severity: FindingSeverity
    public let category: FindingCategory
    public let origin: FindingOrigin
    public let filePath: String
    public let lineNumber: Int?
    public let endLineNumber: Int?
    public let message: String
    public let suggestedFix: String?
    public let confidence: Double?
    public let evidence: String?
    public let sourceTool: String?
    public let blocking: Bool
    public var status: FindingStatus
    public var comments: [FindingComment]
    public let createdAt: Date

    public init(
        id: String = UUID().uuidString,
        severity: FindingSeverity,
        category: FindingCategory,
        origin: FindingOrigin = .reviewer,
        filePath: String,
        lineNumber: Int? = nil,
        endLineNumber: Int? = nil,
        message: String,
        suggestedFix: String? = nil,
        confidence: Double? = nil,
        evidence: String? = nil,
        sourceTool: String? = nil,
        blocking: Bool? = nil,
        status: FindingStatus = .open,
        comments: [FindingComment] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.severity = severity
        self.category = category
        self.origin = origin
        self.filePath = filePath
        self.lineNumber = lineNumber
        self.endLineNumber = endLineNumber
        self.message = message
        self.suggestedFix = suggestedFix
        self.confidence = confidence
        self.evidence = evidence
        self.sourceTool = sourceTool
        self.blocking = blocking ?? (severity == .critical)
        self.status = status
        self.comments = comments
        self.createdAt = createdAt
    }
}

// MARK: - FindingSeverity

public enum FindingSeverity: String, Sendable, Codable, CaseIterable {
    case critical
    case warning
    case suggestion
    case info

    public var sortOrder: Int {
        switch self {
        case .critical: return 0
        case .warning: return 1
        case .suggestion: return 2
        case .info: return 3
        }
    }
}

// MARK: - FindingCategory

public enum FindingCategory: String, Sendable, Codable, CaseIterable {
    case correctness
    case regression
    case concurrency
    case security
    case performance
    case tests
    case maintainability
    case other

    public static let bug: FindingCategory = .correctness
    public static let style: FindingCategory = .maintainability
}

public enum FindingOrigin: String, Sendable, Codable, CaseIterable {
    case reviewer
    case bugHunter = "bugHunter"
    case securityAuditor = "securityAuditor"
    case auditTool = "audit_tool"
}

// MARK: - FindingStatus

public enum FindingStatus: String, Sendable, Codable, CaseIterable {
    case open
    case fixApplied = "fix_applied"
    case dismissed
    case wontFix = "wont_fix"
}

// MARK: - FindingComment

public struct FindingComment: Sendable, Identifiable, Codable {
    public let id: String
    public let author: String
    public let content: String
    public let createdAt: Date

    public init(
        id: String = UUID().uuidString,
        author: String = "agent",
        content: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.author = author
        self.content = content
        self.createdAt = createdAt
    }
}

// MARK: - Parsing from Raw Review Data

extension CodeReviewFinding {
    /// Creates a finding from raw review task data (bridge from legacy pipeline).
    public static func fromRawTask(
        id: String,
        description: String,
        files: [String],
        severity severityStr: String,
        category categoryStr: String? = nil,
        origin: FindingOrigin = .reviewer,
        filePath: String? = nil,
        lineNumber: Int? = nil,
        confidence: Double? = nil,
        evidence: String? = nil,
        sourceTool: String? = nil,
        blocking: Bool? = nil
    ) -> CodeReviewFinding {
        let severity: FindingSeverity
        switch severityStr.lowercased() {
        case "critical", "error", "high":
            severity = .critical
        case "warning", "medium":
            severity = .warning
        case "suggestion", "low", "info":
            severity = .suggestion
        default:
            severity = .warning
        }

        let category: FindingCategory
        if let raw = categoryStr?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            category = FindingCategory.fromStoredValue(raw)
        } else {
            category = Self.inferCategory(from: description)
        }

        return CodeReviewFinding(
            id: id,
            severity: severity,
            category: category,
            origin: origin,
            filePath: filePath ?? files.first ?? "unknown",
            lineNumber: lineNumber,
            message: description,
            suggestedFix: nil,
            confidence: confidence,
            evidence: evidence,
            sourceTool: sourceTool,
            blocking: blocking
        )
    }

    /// Infers finding category from the description text when no explicit category is provided.
    private static func inferCategory(from description: String) -> FindingCategory {
        let lower = description.lowercased()
        if lower.contains("security") || lower.contains("vulnerability") || lower.contains("injection") {
            return .security
        }
        if lower.contains("race") || lower.contains("deadlock") || lower.contains("thread") || lower.contains("concurrency") {
            return .concurrency
        }
        if lower.contains("regression") || lower.contains("crash") || lower.contains("fatal") || lower.contains("force unwrap") {
            return .regression
        }
        if lower.contains("performance") || lower.contains("slow") || lower.contains("O(n") {
            return .performance
        }
        if lower.contains("test") || lower.contains("coverage") {
            return .tests
        }
        if lower.contains("style") || lower.contains("naming") || lower.contains("format")
            || lower.contains("architecture") || lower.contains("coupling") || lower.contains("refactor")
            || lower.contains("doc") || lower.contains("comment") {
            return .maintainability
        }
        return .correctness
    }
}

extension FindingCategory {
    public static func fromStoredValue(_ raw: String) -> FindingCategory {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "correctness", "bug":
            return .correctness
        case "regression":
            return .regression
        case "concurrency":
            return .concurrency
        case "security":
            return .security
        case "performance":
            return .performance
        case "tests", "testing":
            return .tests
        case "maintainability", "style", "architecture", "documentation":
            return .maintainability
        default:
            return .other
        }
    }
}

// MARK: - JSON Serialization Helpers

extension CodeReviewFinding {
    public func toPayload() -> [String: String] {
        var payload: [String: String] = [
            "id": id,
            "severity": severity.rawValue,
            "category": category.rawValue,
            "origin": origin.rawValue,
            "file_path": filePath,
            "message": message,
            "status": status.rawValue,
            "blocking": blocking ? "true" : "false",
        ]
        if let ln = lineNumber { payload["line_number"] = String(ln) }
        if let eln = endLineNumber { payload["end_line_number"] = String(eln) }
        if let fix = suggestedFix { payload["suggested_fix"] = fix }
        if let confidence { payload["confidence"] = String(format: "%.2f", confidence) }
        if let evidence, !evidence.isEmpty { payload["evidence"] = evidence }
        if let sourceTool, !sourceTool.isEmpty { payload["source_tool"] = sourceTool }
        if !comments.isEmpty { payload["comment_count"] = String(comments.count) }
        return payload
    }
}

extension CodeReviewFinding {
    enum CodingKeys: String, CodingKey {
        case id
        case severity
        case category
        case origin
        case filePath
        case lineNumber
        case endLineNumber
        case message
        case suggestedFix
        case confidence
        case evidence
        case sourceTool
        case blocking
        case status
        case comments
        case createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        let severity = try container.decode(FindingSeverity.self, forKey: .severity)
        let rawCategory = try container.decodeIfPresent(String.self, forKey: .category) ?? FindingCategory.other.rawValue
        let origin = try container.decodeIfPresent(FindingOrigin.self, forKey: .origin) ?? .reviewer
        let filePath = try container.decode(String.self, forKey: .filePath)
        let lineNumber = try container.decodeIfPresent(Int.self, forKey: .lineNumber)
        let endLineNumber = try container.decodeIfPresent(Int.self, forKey: .endLineNumber)
        let message = try container.decode(String.self, forKey: .message)
        let suggestedFix = try container.decodeIfPresent(String.self, forKey: .suggestedFix)
        let confidence = try container.decodeIfPresent(Double.self, forKey: .confidence)
        let evidence = try container.decodeIfPresent(String.self, forKey: .evidence)
        let sourceTool = try container.decodeIfPresent(String.self, forKey: .sourceTool)
        let blocking = try container.decodeIfPresent(Bool.self, forKey: .blocking)
        let status = try container.decodeIfPresent(FindingStatus.self, forKey: .status) ?? .open
        let comments = try container.decodeIfPresent([FindingComment].self, forKey: .comments) ?? []
        let createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()

        self.init(
            id: id,
            severity: severity,
            category: FindingCategory.fromStoredValue(rawCategory),
            origin: origin,
            filePath: filePath,
            lineNumber: lineNumber,
            endLineNumber: endLineNumber,
            message: message,
            suggestedFix: suggestedFix,
            confidence: confidence,
            evidence: evidence,
            sourceTool: sourceTool,
            blocking: blocking,
            status: status,
            comments: comments,
            createdAt: createdAt
        )
    }
}
