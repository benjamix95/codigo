import SwiftUI
import CoderEngine

@MainActor
final class ChatStore: ObservableObject {

// MARK: - Conversations (throttled during streaming)

/// Backing storage for `conversations`. Mutations go through the computed
/// property below which calls `conversationsDidChange()` to throttle
/// SwiftUI notifications during streaming. This replaces the previous
/// `@Published var conversations` which fired `objectWillChange` on
/// every single token append — causing a full view hierarchy rebuild
/// per streaming chunk.
private var _conversations: [Conversation] = []

var conversations: [Conversation] {
    get { _conversations }
    set {
        _conversations = newValue
        conversationsDidChange()
    }
}

// MARK: - Throttle (conversations only)

/// Coalesces rapid `objectWillChange` notifications from conversation
/// mutations during streaming. Pattern copied from ToolTraceStore.
/// Outside of streaming, notifications fire immediately.
private var conversationChangeThrottleTask: DispatchWorkItem?
private var lastConversationChangeNotification: Date = .distantPast

private func conversationsDidChange() {
    let now = Date()
    let elapsed = now.timeIntervalSince(lastConversationChangeNotification)
    // During streaming (active tasks), throttle to max 1 notification per 150ms.
    // Outside streaming, notify immediately for responsive UI updates.
    if !isLoading || elapsed > 0.15 {
        lastConversationChangeNotification = now
        conversationChangeThrottleTask?.cancel()
        conversationChangeThrottleTask = nil
        objectWillChange.send()
        return
    }
    conversationChangeThrottleTask?.cancel()
    let work = DispatchWorkItem { [weak self] in
        self?.lastConversationChangeNotification = Date()
        self?.objectWillChange.send()
    }
    conversationChangeThrottleTask = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
}

/// Forces an immediate `objectWillChange` notification, bypassing throttle.
/// Call this when streaming ends to ensure the final state is rendered.
func flushConversationChangeNotification() {
    conversationChangeThrottleTask?.cancel()
    conversationChangeThrottleTask = nil
    lastConversationChangeNotification = Date()
    objectWillChange.send()
}

// MARK: - Other @Published properties (not throttled — rare mutations)

@Published var activeTaskConversationIds: Set<UUID> = []
@Published var taskStartDates: [UUID: Date] = [:]
@Published var planBoards: [UUID: PlanBoard] = [:]
/// Draft text per conversation, persisted to UserDefaults.
@Published var draftTexts: [UUID: String] = [:]
/// Live status text per conversation (shown in sidebar thread rows).
@Published var taskStatusTexts: [UUID: String] = [:]
let userDefaults: UserDefaults

/// Debounce task for coalescing rapid `saveConversations()` calls.
var pendingSaveTask: Task<Void, Never>?
/// Debounce task for coalescing rapid `savePlanBoards()` calls.
var pendingPlanSaveTask: Task<Void, Never>?
/// Debounce task for coalescing rapid `saveDrafts()` calls.
var pendingDraftSaveTask: Task<Void, Never>?
/// Last shared-state signature per conversation to deduplicate plan snapshot writes.
var planSharedSyncSignatureByConversation: [UUID: String] = [:]
/// Guards against async load overwriting more recent saves.
var hasSavedSinceLoad = false
/// True while large conversation history is hydrating asynchronously from disk.
var isAsyncConversationLoadPending = false
/// Background queue for serialization + UserDefaults writes.
static let persistQueue = DispatchQueue(label: "com.solocode.chatstore.persist", qos: .utility)
/// Tracks the last time we persisted during a streaming session (to coalesce saves).
var lastStreamingSaveAt: Date = .distantPast

/// True when any conversation has an active task.
var isLoading: Bool { !activeTaskConversationIds.isEmpty }

private func preferredConversationId(from ids: Set<UUID>) -> UUID? {
    guard !ids.isEmpty else { return nil }
    return ids.max { lhs, rhs in
        let lhsStart = taskStartDates[lhs] ?? .distantPast
        let rhsStart = taskStartDates[rhs] ?? .distantPast
        if lhsStart == rhsStart {
            return lhs.uuidString < rhs.uuidString
        }
        return lhsStart < rhsStart
    }
}

/// Convenience for callers that only need the single-active-task ID.
var activeTaskConversationId: UUID? { preferredConversationId(from: activeTaskConversationIds) }

/// Per-conversation convenience (legacy compat).
var taskStartDate: Date? {
    guard let preferred = activeTaskConversationId else { return nil }
    return taskStartDates[preferred]
}

/// Best-effort target for syncing canonical todo status to plan steps.
/// Prefers active tasks that already own a plan board, then latest plan board overall.
func preferredPlanConversationIdForCanonicalSync() -> UUID? {
    let activePlanConversationIds = Set(activeTaskConversationIds.filter { planBoards[$0] != nil })
    if let preferredActivePlan = preferredConversationId(from: activePlanConversationIds) {
        return preferredActivePlan
    }
    if let latestPlanBoardConversation = planBoards.max(by: {
        if $0.value.updatedAt == $1.value.updatedAt {
            return $0.key.uuidString < $1.key.uuidString
        }
        return $0.value.updatedAt < $1.value.updatedAt
    })?.key {
        return latestPlanBoardConversation
    }
    return activeTaskConversationId
}

/// Check whether a specific conversation has an active task.
func isTaskActive(for conversationId: UUID?) -> Bool {
    guard let id = conversationId else { return false }
    return activeTaskConversationIds.contains(id)
}

/// Start date for a specific conversation's active task.
func taskStartDate(for conversationId: UUID?) -> Date? {
    guard let id = conversationId else { return nil }
    return taskStartDates[id]
}

init(userDefaults: UserDefaults = .standard) {
    self.userDefaults = userDefaults
    loadConversations()
    loadPlanBoards()
    loadDrafts()
    ensureDefaultConversationIfNeeded()
}
    static let asyncLoadThreshold = 100_000 // 100 KB

func ensureDefaultConversationIfNeeded() {
    guard !isAsyncConversationLoadPending else { return }
    guard conversations.isEmpty else { return }
    createConversation(contextId: nil, contextFolderPath: nil, mode: nil)
}

}
