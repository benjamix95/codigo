import SwiftUI
import CoderEngine

struct SidebarView: View {
    @EnvironmentObject var providerRegistry: ProviderRegistry
    @EnvironmentObject var chatStore: ChatStore
    @EnvironmentObject var workspaceStore: WorkspaceStore
    @EnvironmentObject var projectContextStore: ProjectContextStore
    @EnvironmentObject var todoStore: TodoStore
    @EnvironmentObject var toolTraceStore: ToolTraceStore
    @EnvironmentObject var pipelineIntegrationService: PipelineIntegrationService

    @Binding var selectedConversationId: UUID?
    @Binding var showSettings: Bool
    @Binding var isSelectingProjectFolders: Bool
    let preferActiveContextForGlobalThread: Bool

    @State var query = ""
    @State var showArchived = false
    @State var favoritesOnly = false
    @State var contextToRename: ProjectContext?
    @State var conversationToRename: Conversation?
    @State var showSkillsSheet = false
    @State var showRulesSheet = false
    @State private var sidebarComplexLayoutReady = false

    @AppStorage("context_scope_mode") var contextScopeModeRaw = "auto"

    let checkpointGitStore = ConversationCheckpointGitStore()

    var body: some View {
        Group {
            if sidebarComplexLayoutReady {
                sidebarContent
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Color.clear.frame(height: 62)
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading sidebar...")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .task {
                    guard !sidebarComplexLayoutReady else { return }
                    try? await Task.sleep(nanoseconds: 200_000_000)
                    sidebarComplexLayoutReady = true
                }
            }
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
