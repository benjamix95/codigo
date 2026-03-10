import SwiftUI

struct RenameContextSheet: View {
    let context: ProjectContext
    let onDismiss: () -> Void
    @EnvironmentObject var projectContextStore: ProjectContextStore
    @EnvironmentObject var workspaceStore: WorkspaceStore
    @State var newName: String

    init(context: ProjectContext, onDismiss: @escaping () -> Void) {
        self.context = context
        self.onDismiss = onDismiss
        _newName = State(initialValue: context.name)
    }

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Text("Rename context")
                .font(DesignSystem.Typography.title3)
            TextField("Name", text: $newName)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: DesignSystem.Spacing.md) {
                Button("Cancel", role: .cancel, action: onDismiss)
                Button("Save") {
                    let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    projectContextStore.updateName(contextId: context.id, name: trimmed)
                    workspaceStore.syncActiveWorkspace(with: projectContextStore.context(id: context.id))
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(DesignSystem.Spacing.xxl)
        .frame(width: 320)
    }
}

struct RenameConversationSheet: View {
    let conversation: Conversation
    let onDismiss: () -> Void
    @EnvironmentObject var chatStore: ChatStore
    @State var newTitle: String

    init(conversation: Conversation, onDismiss: @escaping () -> Void) {
        self.conversation = conversation
        self.onDismiss = onDismiss
        _newTitle = State(initialValue: conversation.title)
    }

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Text("Rename thread")
                .font(DesignSystem.Typography.title3)
            TextField("Title", text: $newTitle)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: DesignSystem.Spacing.md) {
                Button("Cancel", role: .cancel, action: onDismiss)
                Button("Save") {
                    chatStore.setTitle(conversationId: conversation.id, title: newTitle)
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(DesignSystem.Spacing.xxl)
        .frame(width: 320)
    }
}
