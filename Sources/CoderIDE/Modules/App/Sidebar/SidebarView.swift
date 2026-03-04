import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CoderEngine

struct SidebarView: View {
    @EnvironmentObject var providerRegistry: ProviderRegistry
    @EnvironmentObject var chatStore: ChatStore
    @EnvironmentObject var workspaceStore: WorkspaceStore
    @EnvironmentObject var projectContextStore: ProjectContextStore
    @EnvironmentObject var openFilesStore: OpenFilesStore
    @EnvironmentObject var codexState: CodexStateStore

    @Binding var selectedConversationId: UUID?
    @Binding var showSettings: Bool
    @Binding var isSelectingProjectFolders: Bool
    let preferActiveContextForGlobalThread: Bool

    @State var sidebarQuery = ""
    @State var isSelectingAddFolder = false
    @State var pendingAddFolderWorkspaceId: UUID?
    @State var codexTasks: [CodexCloudTask] = []
    @State var isLoadingTasks = false
    @State var showCreateWorkspace = false
    @State var newWorkspaceName = ""
    @State var workspaceToRename: Workspace?
    @State var conversationToRename: Conversation?
    @State var expandedFolders: Set<String> = []
    @State var showArchived = false
    @State var favoritesOnly = false

    @AppStorage("context_scope_mode") var contextScopeModeRaw = "auto"

    let checkpointGitStore = ConversationCheckpointGitStore()

    var body: some View {
        sidebarContent
    }
}
