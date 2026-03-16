import Foundation

struct ReviewPipelineRustStartRequest: Encodable {
    let schemaVersion: Int
    let sessionId: String
    let conversationId: String?
    let prompt: String
    let workspacePath: String
    let config: ReviewPipelineRustConfig
}

struct ReviewPipelineRustConfig: Encodable {
    let maxWorkers: Int
    let maxReviewRounds: Int
    let enabledPhases: String
    let analysisBackend: String
    let executionBackend: String

    init(config: MultiSwarmReviewConfig) {
        self.maxWorkers = config.maxWorkers
        self.maxReviewRounds = config.maxReviewRounds
        self.enabledPhases = config.enabledPhases.rawValue
        self.analysisBackend = config.analysisBackend
        self.executionBackend = config.executionBackend
    }
}

struct ReviewPipelineRustSessionRequest: Encodable {
    let schemaVersion: Int
    let sessionId: String
}

struct ReviewPipelineRustApplyRequest: Encodable {
    let schemaVersion: Int
    let sessionId: String
    let callback: ReviewPipelineRustCallbackResult
}

struct ReviewPipelineRustCallbackResult: Encodable {
    let kind: String
    let files: [String]
    let findings: [CodeReviewFinding]
    let candidates: [ReviewCandidate]
    let patches: [ReviewPatchArtifact]
    let promotedFindings: [CodeReviewFinding]
    let events: [CodeReviewSessionEvent]
    let audit: ReviewAuditSnapshot?
    let text: String?
    let error: String?
    let testStatus: String?
    let detail: String?

    init(
        kind: String,
        files: [String] = [],
        findings: [CodeReviewFinding] = [],
        candidates: [ReviewCandidate] = [],
        patches: [ReviewPatchArtifact] = [],
        promotedFindings: [CodeReviewFinding] = [],
        events: [CodeReviewSessionEvent] = [],
        audit: ReviewAuditSnapshot? = nil,
        text: String? = nil,
        error: String? = nil,
        testStatus: String? = nil,
        detail: String? = nil
    ) {
        self.kind = kind
        self.files = files
        self.findings = findings
        self.candidates = candidates
        self.patches = patches
        self.promotedFindings = promotedFindings
        self.events = events
        self.audit = audit
        self.text = text
        self.error = error
        self.testStatus = testStatus
        self.detail = detail
    }
}

struct ReviewPipelineRustResponse: Decodable {
    let sessionId: String
    let snapshot: CodeReviewSessionSnapshot
    let step: ReviewPipelineRustStep
    let error: ReviewPipelineRustError?
}

struct ReviewPipelineRustStep: Decodable {
    let kind: String
    let cleanPrompt: String?
    let scopeDescription: String?
    let againstRef: String?
    let resolvedScope: String?
    let files: [String]
    let findingIds: [String]
    let tasks: [ReviewPipelineRustTask]
    let round: Int?
    let reason: String?
    let message: String?
    let maxWorkers: Int?

    private enum CodingKeys: String, CodingKey {
        case kind
        case cleanPrompt
        case scopeDescription
        case againstRef
        case resolvedScope
        case files
        case findingIds
        case tasks
        case round
        case reason
        case message
        case maxWorkers
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(String.self, forKey: .kind)
        cleanPrompt = try container.decodeIfPresent(String.self, forKey: .cleanPrompt)
        scopeDescription = try container.decodeIfPresent(String.self, forKey: .scopeDescription)
        againstRef = try container.decodeIfPresent(String.self, forKey: .againstRef)
        resolvedScope = try container.decodeIfPresent(String.self, forKey: .resolvedScope)
        files = try container.decodeIfPresent([String].self, forKey: .files) ?? []
        findingIds = try container.decodeIfPresent([String].self, forKey: .findingIds) ?? []
        tasks = try container.decodeIfPresent([ReviewPipelineRustTask].self, forKey: .tasks) ?? []
        round = try container.decodeIfPresent(Int.self, forKey: .round)
        reason = try container.decodeIfPresent(String.self, forKey: .reason)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        maxWorkers = try container.decodeIfPresent(Int.self, forKey: .maxWorkers)
    }
}

struct ReviewPipelineRustTask: Codable {
    let id: String
    let description: String
    let files: [String]
    let severity: String
    let category: String?
    let lineNumber: Int?
    let endLineNumber: Int?
    let origin: String
    let confidence: Double?
    let evidence: String?
    let expectedInvariant: String?
    let reproOrReasoning: String?
    let sourceTool: String?
    let blocking: Bool?
}

struct ReviewPipelineRustError: Decodable {
    let code: String
    let message: String
}

extension ReviewPipelineRustTask {
    var reviewTask: CodeReviewMultiSwarmProvider.ReviewTask {
        CodeReviewMultiSwarmProvider.ReviewTask(
            id: id,
            description: description,
            files: files,
            severity: severity,
            category: category,
            lineNumber: lineNumber,
            endLineNumber: endLineNumber,
            origin: FindingOrigin(rawValue: origin) ?? .reviewer,
            confidence: confidence,
            evidence: evidence,
            expectedInvariant: expectedInvariant,
            reproOrReasoning: reproOrReasoning,
            sourceTool: sourceTool,
            blocking: blocking
        )
    }
}
