import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CoderEngine

struct SidebarView: View {
    @EnvironmentObject var chatStore: ChatStore
    @EnvironmentObject var workspaceStore: WorkspaceStore
    @EnvironmentObject var projectContextStore: ProjectContextStore
    @EnvironmentObject var todoStore: TodoStore
    @EnvironmentObject var pipelineIntegrationService: PipelineIntegrationService
    @EnvironmentObject var toolTraceStore: ToolTraceStore

    @Binding var selectedConversationId: UUID?
    @Binding var showSettings: Bool
    @Binding var isSelectingProjectFolders: Bool
    let preferActiveContextForGlobalThread: Bool

    @State var sidebarQuery = ""
    @State var isSelectingAddFolder = false
    @State var pendingAddFolderContextId: UUID?
    @State var contextToRename: ProjectContext?
    @State var conversationToRename: Conversation?
    @State var showArchived = false
    @State var favoritesOnly = false

    @AppStorage("context_scope_mode") var contextScopeModeRaw = "auto"

    let checkpointGitStore = ConversationCheckpointGitStore()

    var body: some View {
        sidebarContent
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
