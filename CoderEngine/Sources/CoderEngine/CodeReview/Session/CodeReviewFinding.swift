import Foundation

// MARK: - CodeReviewFinding

/// Represents a single code review finding (issue, suggestion, or improvement).
public struct CodeReviewFinding: Sendable, Identifiable, Codable {
    public let id: String
    public let severity: FindingSeverity
    public let category: FindingCategory
    public let filePath: String
    public let lineNumber: Int?
    public let endLineNumber: Int?
    public let message: String
    public let suggestedFix: String?
    public var status: FindingStatus
    public var comments: [FindingComment]
    public let createdAt: Date

    public init(
        id: String = UUID().uuidString,
        severity: FindingSeverity,
        category: FindingCategory,
        filePath: String,
        lineNumber: Int? = nil,
        endLineNumber: Int? = nil,
        message: String,
        suggestedFix: String? = nil,
        status: FindingStatus = .open,
        comments: [FindingComment] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.severity = severity
        self.category = category
        self.filePath = filePath
        self.lineNumber = lineNumber
        self.endLineNumber = endLineNumber
        self.message = message
        self.suggestedFix = suggestedFix
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
    case bug
    case security
    case performance
    case style
    case architecture
    case testing
    case documentation
    case other
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
        filePath: String? = nil,
        lineNumber: Int? = nil
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

        return CodeReviewFinding(
            id: id,
            severity: severity,
            category: .bug,
            filePath: filePath ?? files.first ?? "unknown",
            lineNumber: lineNumber,
            message: description,
            suggestedFix: nil
        )
    }
}

// MARK: - JSON Serialization Helpers

extension CodeReviewFinding {
    public func toPayload() -> [String: String] {
        var payload: [String: String] = [
            "id": id,
            "severity": severity.rawValue,
            "category": category.rawValue,
            "file_path": filePath,
            "message": message,
            "status": status.rawValue,
        ]
        if let ln = lineNumber { payload["line_number"] = String(ln) }
        if let eln = endLineNumber { payload["end_line_number"] = String(eln) }
        if let fix = suggestedFix { payload["suggested_fix"] = fix }
        if !comments.isEmpty { payload["comment_count"] = String(comments.count) }
        return payload
    }
}
