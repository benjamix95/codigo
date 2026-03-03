import SwiftUI
import CoderEngine

@MainActor
final class ChatStore: ObservableObject {
@Published var conversations: [Conversation] = []
@Published var activeTaskConversationIds: Set<UUID> = []
@Published var taskStartDates: [UUID: Date] = [:]
@Published var planBoards: [UUID: PlanBoard] = [:]
/// In-memory draft text per conversation (not persisted).
@Published var draftTexts: [UUID: String] = [:]
/// Live status text per conversation (shown in sidebar thread rows).
@Published var taskStatusTexts: [UUID: String] = [:]
let userDefaults: UserDefaults

/// Debounce task for coalescing rapid `saveConversations()` calls.
var pendingSaveTask: Task<Void, Never>?
/// Debounce task for coalescing rapid `savePlanBoards()` calls.
var pendingPlanSaveTask: Task<Void, Never>?
/// Guards against async load overwriting more recent saves.
var hasSavedSinceLoad = false
/// Background queue for serialization + UserDefaults writes.
static let persistQueue = DispatchQueue(label: "com.codigo.chatstore.persist", qos: .utility)
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
    if conversations.isEmpty {
        createConversation(contextId: nil, contextFolderPath: nil, mode: nil)
    }
}
    static let asyncLoadThreshold = 100_000 // 100 KB

}
