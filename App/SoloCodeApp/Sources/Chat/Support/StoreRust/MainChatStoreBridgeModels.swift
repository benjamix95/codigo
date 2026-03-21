import Foundation
import CoderEngine

struct MainChatStoreAttachmentSnapshotBridge: Codable, Equatable {
    let id: String
    let kind: String
    let originalName: String
    let mimeType: String?
    let localPath: String
    let sizeBytes: Int64?
    let createdAt: Date?
}

struct MainChatStorePlanAttachmentSnapshotBridge: Codable, Equatable {
    let historyEntryId: String
    let layoutVersion: Int
    let showExpand: Bool
    let snapshotTitle: String
}

struct MainChatStoreSubagentCardSnapshotBridge: Codable, Equatable {
    let swarmId: String
    let status: String
    let title: String
    let detail: String
    let summary: String?
    let errorCount: Int
    let warningCount: Int?
    let resultPreview: String?
}

struct MainChatStoreTimelineBlockSnapshotBridge: Codable, Equatable {
    let id: String
    let kind: String
    let title: String?
    let text: String
    let items: [String]
    let metadata: [String: String]
    let isCollapsible: Bool
    let isCollapsedByDefault: Bool
}

struct MainChatStoreTurnMetadataSnapshotBridge: Codable, Equatable {
    let turnId: String
    let providerId: String?
    let sequence: Int
    let status: String
    let startedAt: Date?
    let completedAt: Date?
    let updatedAt: Date?
    let isStreaming: Bool
}

struct MainChatStoreMessageSnapshotBridge: Codable, Equatable {
    let id: String
    let role: String
    let content: String
    let primaryTextSnapshot: String?
    let blocks: [MainChatStoreTimelineBlockSnapshotBridge]?
    let turnMetadata: MainChatStoreTurnMetadataSnapshotBridge?
    let isStreaming: Bool
    let imagePaths: [String]?
    let attachments: [MainChatStoreAttachmentSnapshotBridge]?
    let planAttachment: MainChatStorePlanAttachmentSnapshotBridge?
    let reasoningText: String?
    let subagentCards: [MainChatStoreSubagentCardSnapshotBridge]?
}

struct MainChatStorePlanOptionSnapshotBridge: Codable, Equatable {
    let id: Int
    let title: String
    let fullText: String
}

struct MainChatStorePlanStepSnapshotBridge: Codable, Equatable {
    let id: String
    let title: String
    let description: String
    let targetFile: String?
    let status: String
    let linkedFiles: [String]
    let dependsOn: [String]
    let notes: String
    let updatedAt: Date?
}

struct MainChatStorePlanBoardSnapshotBridge: Codable, Equatable {
    let goal: String
    let options: [MainChatStorePlanOptionSnapshotBridge]
    let chosenPath: String?
    let steps: [MainChatStorePlanStepSnapshotBridge]
    let updatedAt: Date?
    let walkthroughMarkdown: String?
    let walkthroughSummary: String?
    let walkthroughOutcome: String?
}

struct MainChatStoreCheckpointGitStateSnapshotBridge: Codable, Equatable {
    let gitRootPath: String
    let gitSnapshotRef: String
}

struct MainChatStoreCheckpointSnapshotBridge: Codable, Equatable {
    let id: String
    let createdAt: Date?
    let messageCount: Int
    let planBoardSnapshot: MainChatStorePlanBoardSnapshotBridge?
    let linkedPlanConversationId: String?
    let linkedPlanBoardSnapshot: MainChatStorePlanBoardSnapshotBridge?
    let gitStates: [MainChatStoreCheckpointGitStateSnapshotBridge]
}

struct MainChatStoreConversationSnapshotBridge: Codable, Equatable {
    let id: String
    let threadRootConversationId: String
    let title: String
    let messages: [MainChatStoreMessageSnapshotBridge]
    let createdAt: Date?
    let contextId: String?
    let contextFolderPath: String?
    let mode: String?
    let preferredProviderId: String?
    let contextMemorySummaryMarkdown: String?
    let contextMemoryGeneratedAt: Date?
    let contextMemorySourceMessageCount: Int?
    let isArchived: Bool
    let isPinned: Bool
    let isFavorite: Bool
    let lastInputTokens: Int?
    let workspaceId: String?
    let adHocFolderPaths: [String]
    let checkpoints: [MainChatStoreCheckpointSnapshotBridge]
}

struct MainChatStoreSnapshotBridge: Codable, Equatable {
    let conversations: [MainChatStoreConversationSnapshotBridge]
    let planBoards: [String: MainChatStorePlanBoardSnapshotBridge]
}

struct MainChatTaskStateSnapshotBridge: Codable, Equatable {
    let conversationId: String
    let startedAt: Date?
    let statusText: String
}

struct MainChatTaskRuntimeStateBridge: Codable, Equatable {
    let taskStates: [MainChatTaskStateSnapshotBridge]
}

struct MainChatTaskRuntimeRequestBridge: Encodable {
    var schemaVersion: Int
    var operation: String
    var state: MainChatTaskRuntimeStateBridge
    var conversationId: String?
    var statusText: String?
    var startedAt: Date?
}

struct MainChatTaskRuntimeResponseBridge: Decodable {
    let schemaVersion: Int
    let error: MainChatStoreBridgeErrorBridge?
    let state: MainChatTaskRuntimeStateBridge?
}

struct MainChatMarkersRequestBridge: Encodable {
    var schemaVersion: Int
    var operation: String
    var text: String
    var aggressive: Bool?
}

struct MainChatMarkersResponseBridge: Decodable {
    let schemaVersion: Int
    let error: MainChatStoreBridgeErrorBridge?
    let text: String?
}

struct MainChatStoreActionRequestBridge: Encodable {
    var schemaVersion: Int
    var action: String
    var snapshot: MainChatStoreSnapshotBridge
    var conversationId: String?
    var messageId: String?
    var checkpointId: String?
    var messageCount: Int?
    var conversation: MainChatStoreConversationSnapshotBridge?
    var message: MainChatStoreMessageSnapshotBridge?
    var planBoard: MainChatStorePlanBoardSnapshotBridge?
    var checkpoint: MainChatStoreCheckpointSnapshotBridge?
    var title: String?
    var mode: String?
    var providerId: String?
    var contextId: String?
    var contextFolderPath: String?
    var workspaceId: String?
    var boolValue: Bool?
    var intValue: Int?
    var text: String?
    var stringList: [String]
    var subagentCards: [MainChatStoreSubagentCardSnapshotBridge]?
}

struct MainChatStoreResponseBridge: Decodable {
    let schemaVersion: Int
    let error: MainChatStoreBridgeErrorBridge?
    let snapshot: MainChatStoreSnapshotBridge?
}

struct MainChatStoreBridgeErrorBridge: Decodable, Equatable {
    let code: String
    let message: String
}

struct MainChatUIStateBridge: Codable {
    let storeSnapshot: MainChatStoreSnapshotBridge
    let runtimeSnapshot: MainChatRuntimeSnapshotBridge?
    let taskRuntimeState: MainChatTaskRuntimeStateBridge?
    let selectedConversationId: String?
    let draftText: String
    let planPanelVisible: Bool
    let followLive: Bool
    let collapsedArtifactIdsByTurn: [String: [String]]
    let autoTodoRuntimeStateByMessage: [String: MainChatUIAutoTodoRuntimeStateBridge]
}

struct MainChatUIConversationSummaryBridge: Decodable {
    let id: String
    let title: String
    let messageCount: Int
    let lastMessagePreview: String?
    let mode: String?
    let preferredProviderId: String?
    let isArchived: Bool
    let isSelected: Bool
    let isLoading: Bool
}

struct MainChatUITimelineBlockSnapshotBridge: Decodable {
    let id: String
    let kind: String
    let title: String?
    let text: String
    let items: [String]
    let metadata: [String: String]
    let isCollapsible: Bool
    let isCollapsedByDefault: Bool
    let isCollapsed: Bool
}

struct MainChatUIMessageSnapshotBridge: Decodable {
    let id: String
    let role: String
    let turnId: String?
    let content: String
    let primaryText: String?
    let reasoningText: String?
    let turnStatus: String?
    let isStreaming: Bool
    let timelineBlocks: [MainChatUITimelineBlockSnapshotBridge]
    let subagentCards: [MainChatStoreSubagentCardSnapshotBridge]
}

struct MainChatUIComposerSnapshotBridge: Decodable { let draftText: String; let canSend: Bool; let canCancel: Bool; let isFollowingLive: Bool }
struct MainChatUITaskSnapshotBridge: Decodable { let isLoading: Bool; let startedAt: Date?; let statusText: String?; let terminalError: String?; let shouldRetryPoll: Bool; let shouldFinalizeStream: Bool }
struct MainChatUIPlanSnapshotBridge: Decodable { let isVisible: Bool; let phase: MainChatPlanPhaseBridge?; let planningStateKind: MainChatPlanningStateKindBridge?; let questionEpoch: Int; let clarificationQuestions: String?; let clarificationQuestionnaire: PlanClarificationQuestionnaire?; let proposalContent: String?; let summaryTitle: String?; let chosenPath: String?; let optionFullTexts: [String]; let optionTitles: [String]; let canonicalTodos: [String]; let goal: String; let stepCount: Int; let shouldHideMarkdown: Bool; let shouldRunInline: Bool; let isReadyToBuild: Bool }
struct MainChatUIAutoTodoRuntimeStateBridge: Codable, Equatable { let todoId: String; let conversationId: String; let title: String; let activeForm: String; let linkedFiles: [String]; let operationCount: Int }
enum MainChatUITodoMutationBridge: String, Decodable { case upsertRuntimeTodo, setStatus, removeTodo, clearMessageRuntimeState }
struct MainChatUITodoPatchBridge: Decodable {
    let mutation: MainChatUITodoMutationBridge?
    let todoId: String?
    let assistantMessageId: String?
    let conversationId: String?
    let providerId: String?
    let title: String?
    let status: String?
    let priority: String?
    let notes: String?
    let activeForm: String?
    let linkedFiles: [String]
    let shouldEmitTraceUpdate: Bool
    let timestamp: Date?
}

struct MainChatUISnapshotBridge: Decodable {
    let selectedConversationId: String?
    let conversations: [MainChatUIConversationSummaryBridge]
    let messages: [MainChatUIMessageSnapshotBridge]
    let composer: MainChatUIComposerSnapshotBridge
    let task: MainChatUITaskSnapshotBridge
    let plan: MainChatUIPlanSnapshotBridge
    let followUpPrompt: String?
    let generatedPrompt: String?
    let isEmpty: Bool
}

struct MainChatUIProjectRequestBridge: Encodable { let schemaVersion: Int; let state: MainChatUIStateBridge }
struct MainChatUIProjectResponseBridge: Decodable { let schemaVersion: Int; let error: MainChatStoreBridgeErrorBridge?; let snapshot: MainChatUISnapshotBridge? }
struct MainChatUIIntentRequestBridge: Encodable { let schemaVersion: Int; let intent: String; let state: MainChatUIStateBridge; let conversationId: String?; let turnId: String?; let artifactId: String?; let text: String?; let timestamp: Date?; let payload: [String: String] }
struct MainChatUIIntentResponseBridge: Decodable { let schemaVersion: Int; let error: MainChatStoreBridgeErrorBridge?; let state: MainChatUIStateBridge?; let snapshot: MainChatUISnapshotBridge?; let todoPatches: [MainChatUITodoPatchBridge] }
