import Foundation

// MARK: - CodeReviewSessionState

/// Thread-safe actor managing the state of a code review session.
/// Follows the DebugStore pattern but uses an actor for Sendable compliance
/// across CoderEngine (non-UI) boundaries.
public actor CodeReviewSessionState {

    // MARK: - Published State

    public private(set) var phase: ReviewSessionPhase = .idle
    public private(set) var findings: [CodeReviewFinding] = []
    public private(set) var events: [CodeReviewSessionEvent] = []
    public private(set) var config: SessionConfig
    public private(set) var scope: ReviewSessionScope?
    public private(set) var currentRound: Int = 0
    public private(set) var activeWorkerCount: Int = 0
    public private(set) var startedAt: Date?
    public private(set) var completedAt: Date?
    public private(set) var lastError: String?

    /// Callback fired on every state mutation (for bridging to @MainActor stores).
    private var onStateChange: (@Sendable (CodeReviewSessionSnapshot) -> Void)?

    // MARK: - Init

    public init(config: SessionConfig = .default) {
        self.config = config
    }

    // MARK: - Observation

    public func setOnStateChange(
        _ handler: @escaping @Sendable (CodeReviewSessionSnapshot) -> Void
    ) {
        onStateChange = handler
    }

    // MARK: - Session Lifecycle

    public func start(scope: ReviewSessionScope) {
        self.phase = .analyzing
        self.scope = scope
        self.findings = []
        self.events = []
        self.currentRound = 0
        self.activeWorkerCount = 0
        self.startedAt = Date()
        self.completedAt = nil
        self.lastError = nil

        let event = CodeReviewSessionEvent.sessionStarted(
            scope: scope.description,
            fileCount: scope.files.count
        )
        events.append(event)
        notifyChange()
    }

    public func complete() {
        phase = .completed
        completedAt = Date()
        let event = CodeReviewSessionEvent(
            type: .sessionCompleted,
            detail: "Review completed with \(findings.count) findings"
        )
        events.append(event)
        notifyChange()
    }

    public func fail(error: String) {
        phase = .failed
        lastError = error
        completedAt = Date()
        events.append(.error(error))
        notifyChange()
    }

    public func reset() {
        phase = .idle
        findings = []
        events = []
        scope = nil
        currentRound = 0
        activeWorkerCount = 0
        startedAt = nil
        completedAt = nil
        lastError = nil
        notifyChange()
    }

    // MARK: - Phase Transitions

    public func setPhase(_ newPhase: ReviewSessionPhase) {
        phase = newPhase
        notifyChange()
    }

    public func startRound(_ round: Int) {
        currentRound = round
        phase = .fixing
        events.append(.roundStarted(round: round, maxRounds: config.maxRounds))
        notifyChange()
    }

    public func setActiveWorkerCount(_ count: Int) {
        activeWorkerCount = count
        notifyChange()
    }

    // MARK: - Findings Management

    public func addFinding(_ finding: CodeReviewFinding) {
        findings.append(finding)
        events.append(.findingAdded(
            findingId: finding.id,
            severity: finding.severity.rawValue,
            filePath: finding.filePath
        ))
        notifyChange()
    }

    public func addFindings(_ newFindings: [CodeReviewFinding]) {
        for finding in newFindings {
            findings.append(finding)
            events.append(.findingAdded(
                findingId: finding.id,
                severity: finding.severity.rawValue,
                filePath: finding.filePath
            ))
        }
        notifyChange()
    }

    public func applyFix(findingId: String) -> Bool {
        guard let idx = findings.firstIndex(where: { $0.id == findingId }) else {
            return false
        }
        findings[idx].status = .fixApplied
        events.append(.findingFixApplied(findingId: findingId))
        notifyChange()
        return true
    }

    public func dismissFinding(
        findingId: String,
        reason: String = "dismissed"
    ) -> Bool {
        guard let idx = findings.firstIndex(where: { $0.id == findingId }) else {
            return false
        }
        findings[idx].status = .dismissed
        events.append(.findingDismissed(findingId: findingId, reason: reason))
        notifyChange()
        return true
    }

    public func addComment(
        findingId: String,
        comment: FindingComment
    ) -> Bool {
        guard let idx = findings.firstIndex(where: { $0.id == findingId }) else {
            return false
        }
        findings[idx].comments.append(comment)
        events.append(CodeReviewSessionEvent(
            type: .findingCommented,
            detail: "Comment added to \(findingId)",
            metadata: [
                "finding_id": findingId,
                "comment_id": comment.id,
            ]
        ))
        notifyChange()
        return true
    }

    public func finding(byId id: String) -> CodeReviewFinding? {
        findings.first { $0.id == id }
    }

    // MARK: - Config

    public func updateConfig(_ newConfig: SessionConfig) {
        config = newConfig
        events.append(CodeReviewSessionEvent(
            type: .configUpdated,
            detail: "Config updated"
        ))
        notifyChange()
    }

    // MARK: - Snapshot

    public func snapshot() -> CodeReviewSessionSnapshot {
        CodeReviewSessionSnapshot(
            phase: phase,
            findings: findings,
            events: events,
            config: config,
            scope: scope,
            currentRound: currentRound,
            activeWorkerCount: activeWorkerCount,
            startedAt: startedAt,
            completedAt: completedAt,
            lastError: lastError
        )
    }

    // MARK: - Private

    private func notifyChange() {
        let snap = snapshot()
        onStateChange?(snap)
    }
}

// MARK: - ReviewSessionPhase

public enum ReviewSessionPhase: String, Sendable, Codable {
    case idle
    case analyzing
    case fixing
    case testing
    case reReviewing = "re_reviewing"
    case completed
    case failed
}

// MARK: - ReviewSessionScope

public struct ReviewSessionScope: Sendable, Codable {
    public let type: ScopeType
    public let files: [String]
    public let ref: String?

    public enum ScopeType: String, Sendable, Codable {
        case uncommitted
        case staged
        case againstRef = "against_ref"
    }

    public var description: String {
        switch type {
        case .uncommitted: return "uncommitted changes (\(files.count) files)"
        case .staged: return "staged changes (\(files.count) files)"
        case .againstRef: return "vs \(ref ?? "unknown") (\(files.count) files)"
        }
    }

    public init(type: ScopeType, files: [String], ref: String? = nil) {
        self.type = type
        self.files = files
        self.ref = ref
    }
}

// MARK: - SessionConfig

public struct SessionConfig: Sendable, Codable {
    public let maxWorkers: Int
    public let maxRounds: Int
    public let analysisBackend: String
    public let executionBackend: String

    public static let `default` = SessionConfig(
        maxWorkers: 6,
        maxRounds: 3,
        analysisBackend: "codex",
        executionBackend: "codex"
    )

    public init(
        maxWorkers: Int = 6,
        maxRounds: Int = 3,
        analysisBackend: String = "codex",
        executionBackend: String = "codex"
    ) {
        self.maxWorkers = max(1, min(12, maxWorkers))
        self.maxRounds = max(1, min(10, maxRounds))
        self.analysisBackend = analysisBackend
        self.executionBackend = executionBackend
    }
}

// MARK: - CodeReviewSessionSnapshot

/// Immutable snapshot of session state for cross-actor transfer.
public struct CodeReviewSessionSnapshot: Sendable {
    public let phase: ReviewSessionPhase
    public let findings: [CodeReviewFinding]
    public let events: [CodeReviewSessionEvent]
    public let config: SessionConfig
    public let scope: ReviewSessionScope?
    public let currentRound: Int
    public let activeWorkerCount: Int
    public let startedAt: Date?
    public let completedAt: Date?
    public let lastError: String?

    public var findingsByFile: [String: [CodeReviewFinding]] {
        Dictionary(grouping: findings, by: \.filePath)
    }

    public var findingsBySeverity: [FindingSeverity: [CodeReviewFinding]] {
        Dictionary(grouping: findings, by: \.severity)
    }

    public var openFindings: [CodeReviewFinding] {
        findings.filter { $0.status == .open }
    }

    public var statusSummary: String {
        let total = findings.count
        let open = findings.filter { $0.status == .open }.count
        let fixed = findings.filter { $0.status == .fixApplied }.count
        let dismissed = findings.filter { $0.status == .dismissed }.count
        return "\(total) findings: \(open) open, \(fixed) fixed, \(dismissed) dismissed"
    }
}
