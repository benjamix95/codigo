import Foundation

// MARK: - RiskBreakdown

/// Scomposizione dettagliata del risk score (§13.4).
public struct RiskBreakdown: Codable, Sendable, Equatable {
    public var filesChangedScore: Double
    public var linesChangedScore: Double
    public var coreModuleScore: Double
    public var testVsProductionRatio: Double
    public var dependentsCount: Int
    public var fileBugHistoryScore: Double

    public init(
        filesChangedScore: Double = 0,
        linesChangedScore: Double = 0,
        coreModuleScore: Double = 0,
        testVsProductionRatio: Double = 0,
        dependentsCount: Int = 0,
        fileBugHistoryScore: Double = 0
    ) {
        self.filesChangedScore = filesChangedScore
        self.linesChangedScore = linesChangedScore
        self.coreModuleScore = coreModuleScore
        self.testVsProductionRatio = testVsProductionRatio
        self.dependentsCount = dependentsCount
        self.fileBugHistoryScore = fileBugHistoryScore
    }

    enum CodingKeys: String, CodingKey {
        case filesChangedScore = "files_changed_score"
        case linesChangedScore = "lines_changed_score"
        case coreModuleScore = "core_module_score"
        case testVsProductionRatio = "test_vs_production_ratio"
        case dependentsCount = "dependents_count"
        case fileBugHistoryScore = "file_bug_history_score"
    }

    /// Calcola il risk score aggregato (§13.4).
    public func computeRiskScore() -> Double {
        let normalized = Double(min(dependentsCount, 10)) / 10.0
        return (filesChangedScore * 0.15)
            + (linesChangedScore * 0.20)
            + (coreModuleScore * 0.15)
            + (testVsProductionRatio * 0.20)
            + (normalized * 0.15)
            + (fileBugHistoryScore * 0.15)
    }
}

// MARK: - PatchManifest

/// Contratto dati del manifest di patch (§6.3).
public struct PatchManifest: Codable, Sendable, Equatable, Identifiable {
    public var id: String { patchId }

    public var patchId: String
    public var jobId: String
    public var taskId: String
    public var provider: String
    public var agentRole: AgentRole
    public var touchedFiles: [String]
    public var unifiedDiffPath: String
    public var riskScore: Double
    public var riskBreakdown: RiskBreakdown?
    public var createdAt: Date
    public var status: PatchStatus
    public var rollbackRef: String?
    public var semanticDiffPath: String?

    public init(
        patchId: String,
        jobId: String,
        taskId: String,
        provider: String,
        agentRole: AgentRole,
        touchedFiles: [String],
        unifiedDiffPath: String,
        riskScore: Double = 0,
        riskBreakdown: RiskBreakdown? = nil,
        createdAt: Date = Date(),
        status: PatchStatus = .proposed,
        rollbackRef: String? = nil,
        semanticDiffPath: String? = nil
    ) {
        self.patchId = patchId
        self.jobId = jobId
        self.taskId = taskId
        self.provider = provider
        self.agentRole = agentRole
        self.touchedFiles = touchedFiles
        self.unifiedDiffPath = unifiedDiffPath
        self.riskScore = riskScore
        self.riskBreakdown = riskBreakdown
        self.createdAt = createdAt
        self.status = status
        self.rollbackRef = rollbackRef
        self.semanticDiffPath = semanticDiffPath
    }

    enum CodingKeys: String, CodingKey {
        case patchId = "patch_id"
        case jobId = "job_id"
        case taskId = "task_id"
        case provider
        case agentRole = "agent_role"
        case touchedFiles = "touched_files"
        case unifiedDiffPath = "unified_diff_path"
        case riskScore = "risk_score"
        case riskBreakdown = "risk_breakdown"
        case createdAt = "created_at"
        case status
        case rollbackRef = "rollback_ref"
        case semanticDiffPath = "semantic_diff_path"
    }

    /// Richiede review extra se risk > 0.7 (§13.4).
    public var requiresExtraReview: Bool { riskScore > 0.7 }

    /// Blast radius check: > 12 file = review extra, > 25 = manual approval (§13.3).
    public var blastRadiusLevel: BlastRadiusLevel {
        let count = touchedFiles.count
        if count > 25 { return .manualApproval }
        if count > 12 { return .extraReview }
        return .normal
    }
}

/// Livello blast radius (§13.3).
public enum BlastRadiusLevel: String, Sendable, Equatable {
    case normal
    case extraReview
    case manualApproval
}

extension PatchManifest: PipelineValidatable {
    public func validate() throws {
        let c = "PatchManifest"
        try PipelineValidationHelpers.requireNonEmpty(patchId, field: "patch_id", contract: c)
        try PipelineValidationHelpers.requireNonEmpty(jobId, field: "job_id", contract: c)
        try PipelineValidationHelpers.requireNonEmpty(taskId, field: "task_id", contract: c)
        try PipelineValidationHelpers.requireNonEmpty(provider, field: "provider", contract: c)
        try PipelineValidationHelpers.requireNonEmptyArray(
            touchedFiles, field: "touched_files", contract: c
        )
        try PipelineValidationHelpers.requireNonEmpty(
            unifiedDiffPath, field: "unified_diff_path", contract: c
        )
        try PipelineValidationHelpers.requireDoubleRange(
            riskScore, range: 0...1, field: "risk_score", contract: c
        )
    }
}
