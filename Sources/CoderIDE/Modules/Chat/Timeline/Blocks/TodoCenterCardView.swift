import SwiftUI

struct TodoCenterCardView: View {
    @ObservedObject var store: TodoStore
    let conversationId: UUID?
    let traceEvents: [ToolTraceEvent]
    let onReviewChanges: () -> Void

    var body: some View {
        let fileChanges = ToolTraceFileChangeMapper.collect(from: traceEvents)
        let items = store.displayTodosForChat(for: conversationId)
        HStack {
            Spacer(minLength: 0)
            ChatTodoExecutionCardView(
                items: items,
                fileChanges: fileChanges,
                onReviewChanges: onReviewChanges
            )
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 800)
    }
}
