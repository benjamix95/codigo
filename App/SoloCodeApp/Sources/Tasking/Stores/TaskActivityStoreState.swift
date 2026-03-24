import CoderEngine
import Foundation

// MARK: - TaskActivityCoreState

/// Groups core activity-tracking @Published properties into a single struct
/// to reduce SwiftUI re-render cascades. A single mutation to `core` fires
/// ONE objectWillChange instead of up to 5 separate notifications.
struct TaskActivityCoreState {
    var activities: [TaskActivity] = []
    var instantGreps: [InstantGrepResult] = []
    var envelopes: [NormalizedEventEnvelope] = []
    var activeOperationsCount: Int = 0
    var unseenLiveEventsCount: Int = 0
}

// MARK: - TaskActivitySwarmState

/// Groups swarm-related @Published properties. Views that only observe
/// swarm state won't re-render when core or code-review state changes.
struct TaskActivitySwarmState {
    var swarmCards: [String: SwarmLiveCardState] = [:]
    var swarmEventsReceivedCount: Int = 0
    var swarmEventsAssignedCount: Int = 0
    var swarmEventsFallbackCount: Int = 0
}

// MARK: - TaskActivityCodeReviewState

/// Groups all 14 code-review @Published properties. Code review UI
/// won't trigger re-renders in the main chat timeline and vice versa.
struct TaskActivityCodeReviewState {
    var codeReviewFindings: [CodeReviewFinding] = []
    var codeReviewEvents: [CodeReviewSessionEvent] = []
    var codeReviewPhase: ReviewSessionPhase = .idle
    var codeReviewStage: ReviewSessionStage = .idle
    var codeReviewFindingsByConversation: [String: [CodeReviewFinding]] = [:]
    var codeReviewEventsByConversation: [String: [CodeReviewSessionEvent]] = [:]
    var codeReviewPhaseByConversation: [String: ReviewSessionPhase] = [:]
    var codeReviewSnapshotsBySession: [String: CodeReviewSessionSnapshot] = [:]
    var codeReviewSessionIdsByConversation: [String: [String]] = [:]
    var selectedCodeReviewSessionIdByConversation: [String: String] = [:]
    var verifiedFindingsEnvelopesBySession: [String: VerifiedFindingsSessionEnvelope] = [:]
    var verifiedFindingsProjectionsByConversation: [String: VerifiedFindingsProjectionSnapshot] = [:]
    var reviewPanelDerivedStateBySession: [String: ReviewPanelDerivedState] = [:]
    var reviewPanelDerivedStateByConversation: [String: ReviewPanelDerivedState] = [:]
}
