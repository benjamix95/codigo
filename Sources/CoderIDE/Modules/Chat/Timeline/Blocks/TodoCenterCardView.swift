import SwiftUI

struct TodoCenterCardView: View {
    @ObservedObject var store: TodoStore
    let conversationId: UUID?
    let onOpenFile: (String) -> Void

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            TodoLiveInlineCard(
                store: store,
                conversationId: conversationId,
                onOpenFile: onOpenFile
            )
            Spacer(minLength: 0)
        }
        .frame(maxWidth: 800)
    }
}
