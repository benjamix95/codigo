import CoderEngine
import Foundation

struct PipelineConversationSnapshot: Equatable {
    let currentJobId: String
    let providerId: String
    let assistantMessageId: UUID
    let planConversationId: UUID?
    let jobState: JobState
    let completedTasks: Int
    let totalTasks: Int
    let isRunning: Bool
    let lastError: String?
    let circuitBreakerActive: Bool
    /// Start time of the job, for elapsed timer display.
    let jobStartTime: Date
}

@MainActor
final class PipelineConversationRuntime {
    enum TeardownState: Equatable {
        case running
        case finalizing
        case finished
    }

    let conversationId: UUID
    let facade: PipelineFacade
    var assistantMessageId: UUID
    let planConversationId: UUID?
    let onCompletion: ((PipelineCompletionContext) -> Void)?
    let rawEventHandler: ((_ type: String, _ payload: [String: String], _ providerId: String, _ conversationId: UUID?) -> Void)?

    var currentJobId: String
    let providerId: String
    var jobState: JobState
    var completedTasks: Int
    var totalTasks: Int
    var isRunning: Bool
    var lastError: String?
    var circuitBreakerActive: Bool
    var wasCancelled: Bool
    var chatTurnState: ChatTurnState
    var nextPipelineSequence: Int
    var activeStreamTask: Task<Void, Never>?
    var teardownState: TeardownState
    let jobStartTime: Date

    /// Cached store snapshot to avoid re-serializing all conversations on
    /// every pipeline event. Built once on first event, then updated from
    /// the Rust boundary response. Cleared on retarget/teardown.
    var cachedStoreSnapshot: MainChatStoreSnapshotBridge?

    /// Cached task runtime state to avoid re-reading chatStore on every
    /// pipeline event. Task runtime only changes on begin_task/end_task/
    /// set_task_status — not on text deltas. Invalidated by those events.
    var cachedTaskRuntimeState: MainChatTaskRuntimeStateBridge?

    /// Eventi stream-only (testo) in attesa di flush verso il bridge Rust (debounce ~16ms).
    var pendingRustBridgeEvents: [ChatPipelineEvent] = []
    var rustBridgeDebounceTask: Task<Void, Never>?

    /// Debounce bridge per ridurre round-trip FFI su delta singoli ad alta frequenza.
    /// Increased from 16ms to 32ms: halves FFI round-trips during streaming
    /// while remaining imperceptible to the user (~30fps text update is smooth).
    static let rustBridgeDebounceNs: UInt64 = 32_000_000

    init(
        conversationId: UUID,
        facade: PipelineFacade,
        jobId: String,
        providerId: String,
        assistantMessageId: UUID,
        planConversationId: UUID?,
        onCompletion: ((PipelineCompletionContext) -> Void)?,
        rawEventHandler: ((_ type: String, _ payload: [String: String], _ providerId: String, _ conversationId: UUID?) -> Void)?
    ) {
        self.conversationId = conversationId
        self.facade = facade
        self.currentJobId = jobId
        self.providerId = providerId
        self.assistantMessageId = assistantMessageId
        self.planConversationId = planConversationId
        self.onCompletion = onCompletion
        self.rawEventHandler = rawEventHandler
        self.jobState = .intake
        self.completedTasks = 0
        self.totalTasks = 0
        self.isRunning = true
        self.lastError = nil
        self.circuitBreakerActive = false
        self.wasCancelled = false
        self.chatTurnState = ChatTurnState(
            conversationId: conversationId,
            assistantMessageId: assistantMessageId,
            turnId: assistantMessageId.uuidString,
            providerId: providerId
        )
        self.nextPipelineSequence = 1
        self.teardownState = .running
        self.jobStartTime = Date()
    }

    var snapshot: PipelineConversationSnapshot {
        PipelineConversationSnapshot(
            currentJobId: currentJobId,
            providerId: providerId,
            assistantMessageId: assistantMessageId,
            planConversationId: planConversationId,
            jobState: jobState,
            completedTasks: completedTasks,
            totalTasks: totalTasks,
            isRunning: isRunning,
            lastError: lastError,
            circuitBreakerActive: circuitBreakerActive,
            jobStartTime: jobStartTime
        )
    }

    func retargetAssistantMessage(
        assistantMessageId: UUID,
        turnId: String
    ) {
        self.assistantMessageId = assistantMessageId
        self.chatTurnState = ChatTurnState(
            conversationId: conversationId,
            assistantMessageId: assistantMessageId,
            turnId: turnId,
            providerId: providerId
        )
        self.nextPipelineSequence = 1
        self.cachedStoreSnapshot = nil
        self.cachedTaskRuntimeState = nil
        rustBridgeDebounceTask?.cancel()
        self.rustBridgeDebounceTask = nil
        self.pendingRustBridgeEvents.removeAll(keepingCapacity: false)
    }

    var isTearDownFinalized: Bool {
        teardownState == .finished
    }

    @discardableResult
    func beginTeardownIfNeeded() -> Bool {
        let oldState = teardownState
        switch teardownState {
        case .running:
            teardownState = .finalizing
            isRunning = false
            NSLog("[PipelineRuntime] teardown %@ -> %@", "\(oldState)", "\(teardownState)")
            return true
        case .finalizing, .finished:
            return false
        }
    }

    func finishTeardown() {
        guard teardownState == .finalizing else { return }
        let oldState = teardownState
        teardownState = .finished
        NSLog("[PipelineRuntime] teardown %@ -> %@", "\(oldState)", "\(teardownState)")
        activeStreamTask = nil
        isRunning = false
    }
}
