import Foundation

// MARK: - JobState

/// Ciclo di vita del job nella pipeline (§5.3).
public enum JobState: String, Codable, Sendable, Equatable, CaseIterable {
    case intake
    case planning
    case contextReady = "context_ready"
    case scheduled
    case executing
    case reviewing
    case validating
    case applying
    case verifying
    case finalized
    case failed
    case rollingBack = "rolling_back"
    case retrying
    case circuitBroken = "circuit_broken"
    case aborted

    /// Stati terminali da cui non si esce.
    public var isTerminal: Bool {
        self == .finalized || self == .aborted
    }

    /// Transizioni valide dalla state machine (§5.3).
    public var validTransitions: Set<JobState> {
        switch self {
        case .intake:        [.planning, .failed]
        case .planning:      [.contextReady, .failed]
        case .contextReady:  [.scheduled, .failed]
        case .scheduled:     [.executing, .failed]
        case .executing:     [.reviewing, .failed]
        case .reviewing:     [.validating, .failed]
        case .validating:    [.applying, .failed]
        case .applying:      [.verifying, .rollingBack]
        case .verifying:     [.finalized, .rollingBack]
        case .finalized:     []
        case .failed:        [.retrying, .aborted, .circuitBroken]
        case .rollingBack:   [.scheduled, .failed]
        case .retrying:      [.scheduled]
        case .circuitBroken: [.aborted]
        case .aborted:       []
        }
    }

    public func canTransition(to next: JobState) -> Bool {
        validTransitions.contains(next)
    }
}

// MARK: - TaskStatus

/// Stato corrente di un task nel DAG.
public enum TaskStatus: String, Codable, Sendable, Equatable, CaseIterable {
    case pending
    case ready
    case running
    case completed
    case failed
    case blocked
    case cancelled
}

// MARK: - TaskType

/// Tipo di task — influenza i pesi del context ranking (§8.3).
public enum TaskType: String, Codable, Sendable, Equatable, CaseIterable {
    case feature
    case bugfix
    case refactor
    case test
    case docs
}

// MARK: - AgentRole
// AgentRole è definito in AgentSwarm/Core/AgentRole.swift
// Usato da tutta la pipeline — include: planner, explorer, coder, debugger,
// reviewer, docWriter, securityAuditor, testWriter

// MARK: - RollbackStrategy

/// Strategia di rollback (§13.1).
public enum RollbackStrategy: String, Codable, Sendable, Equatable, CaseIterable {
    case gitBranch = "git_branch"
    case gitStash = "git_stash"
    case filesystemSnapshot = "filesystem_snapshot"
}

// MARK: - PatchStatus

/// Stato corrente di un patch manifest.
public enum PatchStatus: String, Codable, Sendable, Equatable, CaseIterable {
    case proposed
    case approved
    case applied
    case rolledBack = "rolled_back"
    case rejected
}

// MARK: - EventType

/// Tipi evento minimi dell'event bus (§6.9).
public enum PipelineEventType: String, Codable, Sendable, Equatable, CaseIterable {
    case taskStarted = "task_started"
    case taskCompleted = "task_completed"
    case taskFailed = "task_failed"
    case patchCreated = "patch_created"
    case reviewFailed = "review_failed"
    case reviewPassed = "review_passed"
    case lockAcquired = "lock_acquired"
    case lockReleased = "lock_released"
    case rollbackStarted = "rollback_started"
    case rollbackCompleted = "rollback_completed"
    case circuitBreakerTriggered = "circuit_breaker_triggered"
    case providerHealthChanged = "provider_health_changed"
    case schedulerBackpressure = "scheduler_backpressure"
    case jobTimeout = "job_timeout"
    case errorBudgetLow = "error_budget_low"
    case patchApplyFailed = "patch_apply_failed"
    case verifyFailedRollback = "verify_failed_rollback"
    case rollbackFailed = "rollback_failed"
    case securityBlock = "security_block"
    case textDelta = "text_delta"
    case textReplace = "text_replace"
    case rawAgentEvent = "raw_agent_event"
}

// MARK: - DeliveryStatus

/// Stato di consegna di un evento bus (§6.9).
public enum DeliveryStatus: String, Codable, Sendable, Equatable, CaseIterable {
    case pending
    case delivered
    case failed
    case deadLettered = "dead_lettered"
}

// MARK: - CircuitBreakerPhase

/// Stato del circuit breaker (§17.1).
public enum CircuitBreakerPhase: String, Codable, Sendable, Equatable, CaseIterable {
    case closed
    case open
    case halfOpen = "half_open"
}

// MARK: - ProviderHealthStatus

/// Stato di salute del provider (§6.5).
public enum ProviderHealthStatus: String, Codable, Sendable, Equatable, CaseIterable {
    case healthy
    case unhealthy
    case recovering
}

// MARK: - ReviewScope

/// Scope di review (§6.4).
public enum ReviewScope: String, Codable, Sendable, Equatable, CaseIterable {
    case uncommitted
    case staged
    case againstRef = "against_ref"
}

// MARK: - ReviewPhase

/// Fase corrente della sessione di review nella pipeline.
public enum ReviewPhase: String, Codable, Sendable, Equatable, CaseIterable {
    case pending
    case reviewing
    case completed
    case blocked
}

// MARK: - FindingSeverity & FindingStatus
// Definiti in CodeReview/Session/CodeReviewFinding.swift
// FindingSeverity: critical, warning, suggestion, info
// FindingStatus: open, fixApplied, dismissed, wontFix

// MARK: - ActionType

/// Tipi di action nell'agent_action_envelope (§6.8).
public enum ActionType: String, Codable, Sendable, Equatable, CaseIterable {
    case patchProposal = "patch_proposal"
    case analysisNote = "analysis_note"
    case testUpdate = "test_update"
    case docUpdate = "doc_update"
    case docChangelog = "doc_changelog"
    case docFlowUpdate = "doc_flow_update"
}

// MARK: - DocCategory

/// Categorie documentazione docWriter (§6.14).
public enum DocCategory: String, Codable, Sendable, Equatable, CaseIterable {
    case apiReference = "api_reference"
    case architecture
    case guide
    case changelog
    case flow
    case adr
    case inline
}

// MARK: - SemanticChangeType

/// Tipi di cambio semantico nel semantic diff (§8.6).
public enum SemanticChangeType: String, Codable, Sendable, Equatable, CaseIterable {
    case functionSignatureChanged = "function_signature_changed"
    case functionBodyChanged = "function_body_changed"
    case functionAdded = "function_added"
    case functionRemoved = "function_removed"
    case typeChanged = "type_changed"
    case propertyChanged = "property_changed"
    case importAdded = "import_added"
    case importRemoved = "import_removed"
    case accessLevelChanged = "access_level_changed"
    case protocolConformanceChanged = "protocol_conformance_changed"
    case cosmeticOnly = "cosmetic_only"
}

// MARK: - SemanticImpact

/// Livello di impatto semantico (§8.6).
public enum SemanticImpact: String, Codable, Sendable, Equatable, CaseIterable {
    case breakingChange = "breaking_change"
    case behaviorChange = "behavior_change"
    case dependencyChange = "dependency_change"
    case cosmetic
}

// MARK: - RiskLevel

/// Livello di rischio di un task (§6.2).
public enum RiskLevel: String, Codable, Sendable, Equatable, CaseIterable {
    case low
    case medium
    case high
    case critical
}

// MARK: - PipelineMode

/// Modalità operativa della pipeline (§7).
public enum PipelineMode: String, Codable, Sendable, Equatable, CaseIterable {
    case strict
    case fast
}
