import Foundation

// MARK: - AgentAction

/// Singola azione nell'envelope (§6.8).
public struct AgentAction: Codable, Sendable, Equatable {
    public var type: ActionType
    public var file: String?
    public var diff: String?
    public var docCategory: DocCategory?
    public var scope: [String]?
    public var summary: String?
    public var affectedFlow: String?

    public init(
        type: ActionType,
        file: String? = nil,
        diff: String? = nil,
        docCategory: DocCategory? = nil,
        scope: [String]? = nil,
        summary: String? = nil,
        affectedFlow: String? = nil
    ) {
        self.type = type
        self.file = file
        self.diff = diff
        self.docCategory = docCategory
        self.scope = scope
        self.summary = summary
        self.affectedFlow = affectedFlow
    }

    enum CodingKeys: String, CodingKey {
        case type
        case file
        case diff
        case docCategory = "doc_category"
        case scope
        case summary
        case affectedFlow = "affected_flow"
    }
}

// MARK: - AgentActionEnvelope

/// Envelope JSON restituito da ogni agente (§6.8).
/// Output free-text non tipizzato MUST essere rifiutato.
public struct AgentActionEnvelope: Codable, Sendable, Equatable {
    public var agentId: String
    public var agentName: String
    public var agentRole: AgentRole
    public var jobId: String
    public var taskId: String
    public var correlationId: String?
    public var actions: [AgentAction]
    public var confidence: Double
    public var notes: String?

    public init(
        agentId: String,
        agentName: String,
        agentRole: AgentRole,
        jobId: String,
        taskId: String,
        correlationId: String? = nil,
        actions: [AgentAction],
        confidence: Double,
        notes: String? = nil
    ) {
        self.agentId = agentId
        self.agentName = agentName
        self.agentRole = agentRole
        self.jobId = jobId
        self.taskId = taskId
        self.correlationId = correlationId
        self.actions = actions
        self.confidence = confidence
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey {
        case agentId = "agent_id"
        case agentName = "agent_name"
        case agentRole = "agent_role"
        case jobId = "job_id"
        case taskId = "task_id"
        case correlationId = "correlation_id"
        case actions
        case confidence
        case notes
    }
}

extension AgentActionEnvelope: PipelineValidatable {
    public func validate() throws {
        let c = "AgentActionEnvelope"
        try PipelineValidationHelpers.requireNonEmpty(agentId, field: "agent_id", contract: c)
        try PipelineValidationHelpers.requireNonEmpty(agentName, field: "agent_name", contract: c)
        try PipelineValidationHelpers.requireNonEmpty(jobId, field: "job_id", contract: c)
        try PipelineValidationHelpers.requireNonEmpty(taskId, field: "task_id", contract: c)
        try PipelineValidationHelpers.requireNonEmptyArray(
            actions, field: "actions", contract: c
        )
        try PipelineValidationHelpers.requireDoubleRange(
            confidence, range: 0...1, field: "confidence", contract: c
        )
        if !agentName.contains("-") {
            throw PipelineValidationError.constraintViolation(
                field: "agent_name", contract: c,
                reason: "agent_name must follow {taskLabel}-{role} convention"
            )
        }
    }
}
