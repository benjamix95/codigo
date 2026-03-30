import Foundation
import CoderEngine

struct SidebarThreadRenderState {
    let hasDraft: Bool
    let isActive: Bool
    let isStreaming: Bool
    let statusText: String?
    let todoProgressLabel: String?
    let metrics: SidebarThreadMetrics

    static let empty = SidebarThreadRenderState(
        hasDraft: false,
        isActive: false,
        isStreaming: false,
        statusText: nil,
        todoProgressLabel: nil,
        metrics: .empty
    )
}

struct SidebarThreadRenderFingerprint: Equatable {
    let threads: [Thread]

    struct Thread: Equatable {
        let id: UUID
        let hasDraft: Bool
        let isActive: Bool
        let isStreaming: Bool
        let statusText: String?
        let todoProgressLabel: String?
        let metrics: SidebarThreadMetrics
    }
}

extension SidebarThreadSnapshotBuilder {
    struct RenderStateUpdate {
        let renderStates: [UUID: SidebarThreadRenderState]
        let fingerprint: SidebarThreadRenderFingerprint
    }

    private struct RenderComputationContext {
        let activeConversationScopes: Set<String>

        @inline(__always)
        func hasVisibleTaskActivity(for conversationId: UUID) -> Bool {
            activeConversationScopes.contains(conversationId.uuidString.lowercased())
        }
    }

    @MainActor
    static func buildRenderStates(
        conversations: [Conversation],
        chatStore: ChatStore,
        taskActivityStore: TaskActivityStore,
        todoStore: TodoStore,
        toolTraceStore: ToolTraceStore
    ) -> [UUID: SidebarThreadRenderState] {
        renderStateUpdate(
            conversations: conversations,
            chatStore: chatStore,
            taskActivityStore: taskActivityStore,
            todoStore: todoStore,
            toolTraceStore: toolTraceStore
        ).renderStates
    }

    @MainActor
    static func renderFingerprint(
        conversations: [Conversation],
        chatStore: ChatStore,
        taskActivityStore: TaskActivityStore,
        todoStore: TodoStore,
        toolTraceStore: ToolTraceStore
    ) -> SidebarThreadRenderFingerprint {
        renderStateUpdate(
            conversations: conversations,
            chatStore: chatStore,
            taskActivityStore: taskActivityStore,
            todoStore: todoStore,
            toolTraceStore: toolTraceStore
        ).fingerprint
    }

    @MainActor
    static func buildRenderStatesAndFingerprint(
        conversations: [Conversation],
        chatStore: ChatStore,
        taskActivityStore: TaskActivityStore,
        todoStore: TodoStore,
        toolTraceStore: ToolTraceStore
    ) -> (renderStates: [UUID: SidebarThreadRenderState], fingerprint: SidebarThreadRenderFingerprint) {
        let update = renderStateUpdate(
            conversations: conversations,
            chatStore: chatStore,
            taskActivityStore: taskActivityStore,
            todoStore: todoStore,
            toolTraceStore: toolTraceStore
        )
        return (update.renderStates, update.fingerprint)
    }

    @MainActor
    private static func buildRenderState(
        for conversation: Conversation,
        renderContext: RenderComputationContext,
        chatStore: ChatStore,
        todoStore: TodoStore,
        toolTraceStore: ToolTraceStore
    ) -> SidebarThreadRenderState {
        let hasDraft = !(chatStore.draftTexts[conversation.id]?
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasVisibleTaskActivity = renderContext.hasVisibleTaskActivity(for: conversation.id)
        let isStreaming = chatStore.isAssistantStreaming(in: conversation.id)
            && hasVisibleTaskActivity
        let statusText = hasVisibleTaskActivity ? chatStore.taskStatusTexts[conversation.id] : nil
        let chatTodos = todoStore.displayTodosForChat(for: conversation.id)
        return SidebarThreadRenderState(
            hasDraft: hasDraft,
            isActive: hasVisibleTaskActivity,
            isStreaming: isStreaming,
            statusText: statusText,
            todoProgressLabel: SidebarThreadTodoCaption.progressLabel(displayTodos: chatTodos),
            metrics: SidebarThreadMetrics.compute(
                conversation: conversation,
                toolTraceStore: toolTraceStore
            )
        )
    }

    @MainActor
    private static func renderStateUpdate(
        conversations: [Conversation],
        chatStore: ChatStore,
        taskActivityStore: TaskActivityStore,
        todoStore: TodoStore,
        toolTraceStore: ToolTraceStore
    ) -> RenderStateUpdate {
        let renderContext = RenderComputationContext(
            activeConversationScopes: taskActivityStore.concreteNonSwarmConversationScopesIncludingPending()
        )
        var renderStates: [UUID: SidebarThreadRenderState] = [:]
        renderStates.reserveCapacity(conversations.count)
        var threads: [SidebarThreadRenderFingerprint.Thread] = []
        threads.reserveCapacity(conversations.count)

        for conversation in conversations {
            let renderState = buildRenderState(
                for: conversation,
                renderContext: renderContext,
                chatStore: chatStore,
                todoStore: todoStore,
                toolTraceStore: toolTraceStore
            )
            renderStates[conversation.id] = renderState
            threads.append(
                SidebarThreadRenderFingerprint.Thread(
                    id: conversation.id,
                    hasDraft: renderState.hasDraft,
                    isActive: renderState.isActive,
                    isStreaming: renderState.isStreaming,
                    statusText: renderState.statusText,
                    todoProgressLabel: renderState.todoProgressLabel,
                    metrics: renderState.metrics
                )
            )
        }

        return RenderStateUpdate(
            renderStates: renderStates,
            fingerprint: SidebarThreadRenderFingerprint(threads: threads)
        )
    }
}
