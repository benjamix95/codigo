import SwiftUI
import CoderEngine

struct RenameWorkspaceSheet: View {
    let workspace: Workspace
    let onDismiss: () -> Void
    @EnvironmentObject var workspaceStore: WorkspaceStore
    @State var newName: String

    init(workspace: Workspace, onDismiss: @escaping () -> Void) {
        self.workspace = workspace
        self.onDismiss = onDismiss
        _newName = State(initialValue: workspace.name)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Rename Workspace")
                .font(.title3)
            TextField("Name", text: $newName)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 12) {
                Button("Cancel", role: .cancel, action: onDismiss)
                Button("Save") {
                    var updated = workspace
                    updated.name = newName.trimmingCharacters(in: .whitespaces)
                    workspaceStore.update(updated)
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
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
        VStack(spacing: 16) {
            Text("Rename thread")
                .font(.title3)
            TextField("Title", text: $newTitle)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 12) {
                Button("Cancel", role: .cancel, action: onDismiss)
                Button("Save") {
                    chatStore.setTitle(conversationId: conversation.id, title: newTitle)
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 320)
    }
}

struct CreateWorkspaceSheetView: View {
    @ObservedObject var workspaceStore: WorkspaceStore
    @Binding var newWorkspaceName: String
    @Binding var showCreateWorkspace: Bool
    let onCreated: (UUID) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "folder.badge.plus")
                .font(.largeTitle)
                .foregroundStyle(Color.accentColor)
            Text("New Workspace")
                .font(.title3)
            VStack(alignment: .leading, spacing: 4) {
                Text("Name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Workspace name", text: $newWorkspaceName)
                    .textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 12) {
                Button("Cancel", role: .cancel) {
                    newWorkspaceName = ""
                    showCreateWorkspace = false
                }
                Button("Create") {
                    workspaceStore.createEmpty(name: newWorkspaceName)
                    if let ws = workspaceStore.workspaces.last { onCreated(ws.id) }
                    newWorkspaceName = ""
                    showCreateWorkspace = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(newWorkspaceName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 360)
    }
}
