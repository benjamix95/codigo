import Foundation

// MARK: - CodeReviewSessionState

/// Thread-safe actor managing the state of a code review session.
/// Follows the DebugStore pattern but uses an actor for Sendable compliance
/// across CoderEngine (non-UI) boundaries.
public actor CodeReviewSessionState {

    // MARK: - Published State

    public let sessionId: String
    public let conversationId: UUID?
    var phase: ReviewSessionPhase = .idle
    var stage: ReviewSessionStage = .idle
    var findings: [CodeReviewFinding] = []
    var events: [CodeReviewSessionEvent] = []
    var config: SessionConfig
    var mutationSequence: UInt64 = 0
    var scope: ReviewSessionScope?
    var workspacePath: String?
    var currentRound: Int = 0
    var activeWorkerCount: Int = 0
    var startedAt: Date?
    var completedAt: Date?
    var analysisCompletedAt: Date?
    var lastError: String?
    var currentJobId: String?
    var lastTestStatus: ReviewSessionTestStatus?

    /// Callback fired on every state mutation (for bridging to @MainActor stores).
    private var onStateChange: (@Sendable (CodeReviewSessionSnapshot) -> Void)?

    // MARK: - Init

    public init(
        sessionId: String = UUID().uuidString.lowercased(),
        conversationId: UUID? = nil,
        config: SessionConfig = .default,
        onStateChange: (@Sendable (CodeReviewSessionSnapshot) -> Void)? = nil
    ) {
        self.sessionId = sessionId
        self.conversationId = conversationId
        self.config = config
        self.onStateChange = onStateChange
    }

    // MARK: - Observation

    public func setOnStateChange(
        _ handler: @escaping @Sendable (CodeReviewSessionSnapshot) -> Void
    ) {
        onStateChange = handler
    }

    // MARK: - Snapshot

    public func snapshot() -> CodeReviewSessionSnapshot {
        CodeReviewSessionSnapshot(
            sessionId: sessionId,
            conversationId: conversationId,
            mutationSequence: mutationSequence,
            phase: phase,
            stage: stage,
            findings: findings,
            events: events,
            config: config,
            scope: scope,
            workspacePath: workspacePath,
            currentRound: currentRound,
            activeWorkerCount: activeWorkerCount,
            startedAt: startedAt,
            completedAt: completedAt,
            analysisCompletedAt: analysisCompletedAt,
            lastError: lastError,
            currentJobId: currentJobId,
            lastTestStatus: lastTestStatus,
            lastUpdatedAt: Date()
        )
    }

    // MARK: - Private

    /// Hard cap on events to prevent unbounded growth.
    private let eventsHardCap = 500
    func notifyChange() {
        if events.count > eventsHardCap {
            events = Array(events.suffix(eventsHardCap))
        }
        mutationSequence &+= 1
        let snap = snapshot()
        if let handler = onStateChange {
            Task { @MainActor in handler(snap) }
        }
    }
}
