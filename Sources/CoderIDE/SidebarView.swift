import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CoderEngine

struct SidebarView: View {
    @EnvironmentObject var chatStore: ChatStore
    @EnvironmentObject var workspaceStore: WorkspaceStore
    @EnvironmentObject var openFilesStore: OpenFilesStore
    @EnvironmentObject var codexState: CodexStateStore
    @EnvironmentObject var todoStore: TodoStore
    @Binding var selectedConversationId: UUID?
    @State private var isSelectingAddFolder = false
    @State private var codexTasks: [CodexCloudTask] = []
    @State private var isLoadingTasks = false
    @State private var pendingAddFolderWorkspaceId: UUID?
    @State private var showCreateWorkspace = false
    @State private var newWorkspaceName = ""
    @State private var expandedFolders: Set<String> = []
    @State private var workspaceToRename: Workspace?
    @State private var isSelectingAdHocFolders = false

    var body: some View {
        List {
            fileMenuSection

            workspaceSection

            if effectiveContext(for: selectedConversationId, chatStore: chatStore, workspaceStore: workspaceStore).hasContext {
                fileBrowserSection
            }

            todoSection

            if codexState.status.isInstalled && codexState.status.isLoggedIn {
                codexTasksSection
            }

            conversationsSection
        }
        .listStyle(.sidebar)
        .navigationTitle("Codigo")
        .sheet(isPresented: $showCreateWorkspace) {
            CreateWorkspaceSheetView(
                workspaceStore: workspaceStore,
                newWorkspaceName: $newWorkspaceName,
                showCreateWorkspace: $showCreateWorkspace,
                onCreated: { newWorkspaceId in
                    workspaceStore.activeWorkspaceId = newWorkspaceId
                    if let convId = selectedConversationId {
                        chatStore.setWorkspace(conversationId: convId, workspaceId: newWorkspaceId)
                    } else {
                        let newConvId = chatStore.createConversation(workspaceId: newWorkspaceId)
                        selectedConversationId = newConvId
                    }
                }
            )
        }
        .fileImporter(
            isPresented: $isSelectingAddFolder,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleAddFolderSelection(result: result)
        }
        .fileImporter(
            isPresented: $isSelectingAdHocFolders,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: true
        ) { result in
            handleAdHocFolderSelection(result: result)
        }
        .sheet(item: $workspaceToRename) { ws in
            RenameWorkspaceSheet(workspace: ws, onDismiss: { workspaceToRename = nil })
                .environmentObject(workspaceStore)
        }
        .onChange(of: selectedConversationId) { _, _ in
            if let conv = chatStore.conversation(for: selectedConversationId),
               let wsId = conv.workspaceId {
                workspaceStore.activeWorkspaceId = wsId
            } else if chatStore.conversation(for: selectedConversationId) != nil {
                workspaceStore.activeWorkspaceId = nil
            }
        }
    }

    // MARK: - File Menu Section
    private var fileMenuSection: some View {
        Section("File") {
            Menu {
                Button {
                    isSelectingAdHocFolders = true
                } label: {
                    Label("Apri progetto...", systemImage: "folder.badge.plus")
                }
                Button {
                    showCreateWorkspace = true
                } label: {
                    Label("Nuovo workspace...", systemImage: "folder.badge.gearshape")
                }
                Divider()
                Button {
                    clearConversationContext()
                } label: {
                    Label("Chiudi contesto", systemImage: "xmark.circle")
                }
                .disabled(!effectiveContext(for: selectedConversationId, chatStore: chatStore, workspaceStore: workspaceStore).hasContext)
            } label: {
                Label("Progetto e file", systemImage: "doc.text.fill")
            }
        }
    }

    // MARK: - Workspace Section
    private var activeWorkspaceForConversation: Workspace? {
        guard let conv = chatStore.conversation(for: selectedConversationId),
              let wsId = conv.workspaceId else { return nil }
        return workspaceStore.workspaces.first { $0.id == wsId }
    }

    private var workspaceSection: some View {
        Section {
            if let ws = activeWorkspaceForConversation {
                activeWorkspaceRow(ws)
                ForEach(ws.folderPaths, id: \.self) { path in
                    folderPathRow(path: path, workspaceId: ws.id)
                }
                if workspaceStore.workspaces.count > 1 {
                    ForEach(workspaceStore.workspaces.filter { $0.id != ws.id }) { other in
                        otherWorkspaceRow(other)
                    }
                }
            } else if !workspaceStore.workspaces.isEmpty {
                ForEach(workspaceStore.workspaces) { ws in
                    Button {
                        handleWorkspaceSelected(ws)
                    } label: {
                        Label(ws.name, systemImage: "folder")
                    }
                }
            } else {
                Button {
                    showCreateWorkspace = true
                } label: {
                    Label("Apri cartella", systemImage: "folder.badge.plus")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            HStack {
                Text("Workspace")
                Spacer()
                Button {
                    showCreateWorkspace = true
                } label: {
                    Image(systemName: "plus")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func activeWorkspaceRow(_ ws: Workspace) -> some View {
        HStack {
            Menu {
                Button { workspaceToRename = ws } label: {
                    Label("Rinomina workspace...", systemImage: "pencil")
                }
                Button { showCreateWorkspace = true } label: {
                    Label("Crea nuovo workspace...", systemImage: "plus")
                }
            } label: {
                Label(ws.name, systemImage: "folder.fill")
                    .font(.subheadline.weight(.medium))
            }
            .menuStyle(.borderlessButton)
            Spacer()
            Button {
                pendingAddFolderWorkspaceId = ws.id
                isSelectingAddFolder = true
            } label: {
                Image(systemName: "plus.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private func folderPathRow(path: String, workspaceId: UUID) -> some View {
        HStack {
            Label((path as NSString).lastPathComponent, systemImage: "folder")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                workspaceStore.removeFolder(from: workspaceId, path: path)
            } label: {
                Image(systemName: "minus.circle")
                    .font(.caption2)
                    .foregroundStyle(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 8)
    }

    private func otherWorkspaceRow(_ ws: Workspace) -> some View {
        Button {
            handleWorkspaceSelected(ws)
        } label: {
            Label(ws.name, systemImage: "folder")
                .foregroundStyle(.secondary)
        }
    }

    private func handleWorkspaceSelected(_ ws: Workspace) {
        workspaceStore.activeWorkspaceId = ws.id
        if let convId = selectedConversationId {
            chatStore.setWorkspace(conversationId: convId, workspaceId: ws.id)
        } else {
            let newId = chatStore.createConversation(workspaceId: ws.id)
            selectedConversationId = newId
        }
    }

    private func clearConversationContext() {
        guard let convId = selectedConversationId else { return }
        chatStore.setWorkspace(conversationId: convId, workspaceId: nil)
        chatStore.setAdHocPaths(conversationId: convId, paths: [])
        workspaceStore.activeWorkspaceId = nil
    }

    // MARK: - File Browser Section
    private var fileBrowserSection: some View {
        let ctx = effectiveContext(for: selectedConversationId, chatStore: chatStore, workspaceStore: workspaceStore)
        return Section("Files") {
            ForEach(ctx.folderPaths, id: \.self) { path in
                fileBrowser(for: path)
            }
        }
    }

    private func fileBrowser(for path: String) -> some View {
        Group {
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: path) {
                ForEach(contents.sorted(), id: \.self) { item in
                    let itemPath = (path as NSString).appendingPathComponent(item)
                    let isDirectory = (try? FileManager.default.attributesOfItem(atPath: itemPath)[.type] as? FileAttributeType == .typeDirectory) ?? false
                    fileRow(name: item, path: itemPath, isDirectory: isDirectory, depth: 0)
                }
            }
        }
    }

    private func fileRow(name: String, path: String, isDirectory: Bool, depth: Int) -> AnyView {
        let isExpanded = expandedFolders.contains(path)
        return AnyView(
            VStack(spacing: 0) {
                Button {
                    if isDirectory {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if expandedFolders.contains(path) {
                                expandedFolders.remove(path)
                            } else {
                                expandedFolders.insert(path)
                            }
                        }
                    } else {
                        openFilesStore.openFile(path)
                    }
                } label: {
                    HStack(spacing: 4) {
                        if depth > 0 {
                            Spacer()
                                .frame(width: CGFloat(depth) * 12)
                        }
                        Image(systemName: fileIcon(for: name, isDirectory: isDirectory, isExpanded: isExpanded))
                            .font(.caption2)
                            .foregroundStyle(fileIconColor(for: name, isDirectory: isDirectory))
                            .frame(width: 16)
                        Text(name)
                            .font(.caption)
                            .foregroundStyle(openFilesStore.openFilePath == path ? Color.accentColor : .primary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if isDirectory && isExpanded {
                    fileContents(for: path, depth: depth + 1)
                }
            }
        )
    }

    private func fileContents(for path: String, depth: Int) -> AnyView {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: path) else {
            return AnyView(EmptyView())
        }
        return AnyView(
            ForEach(contents.sorted(), id: \.self) { item in
                let itemPath = (path as NSString).appendingPathComponent(item)
                let isSubDirectory = (try? FileManager.default.attributesOfItem(atPath: itemPath)[.type] as? FileAttributeType == .typeDirectory) ?? false
                fileRow(name: item, path: itemPath, isDirectory: isSubDirectory, depth: depth)
            }
        )
    }

    private func fileIcon(for name: String, isDirectory: Bool, isExpanded: Bool) -> String {
        if isDirectory { return isExpanded ? "chevron.down" : "chevron.right" }
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "ts", "jsx", "tsx": return "curlybraces"
        case "py": return "chevron.left.forwardslash.chevron.right"
        case "md", "markdown": return "doc.text"
        case "json": return "curlybraces.square"
        case "html", "css": return "globe"
        case "png", "jpg", "jpeg", "gif", "svg": return "photo"
        default: return "doc"
        }
    }

    private func fileIconColor(for name: String, isDirectory: Bool) -> Color {
        if isDirectory { return .accentColor }
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return .orange
        case "js", "ts", "jsx", "tsx": return .yellow
        case "py": return .green
        case "json": return .secondary
        default: return .secondary
        }
    }

    // MARK: - To-do Section
    private var todoSection: some View {
        Section("To-do") {
            TodoListView(store: todoStore)
        }
    }

    // MARK: - Codex Tasks Section
    private var codexTasksSection: some View {
        Section {
            if isLoadingTasks {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Caricamento...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if codexTasks.isEmpty {
                Button {
                    loadCodexTasks()
                } label: {
                    Label("Aggiorna", systemImage: "arrow.clockwise")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(codexTasks, id: \.id) { task in
                    codexTaskRow(task)
                }
                Button {
                    loadCodexTasks()
                } label: {
                    Label("Aggiorna", systemImage: "arrow.clockwise")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Task Cloud")
        }
    }

    private func codexTaskRow(_ task: CodexCloudTask) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(task.title ?? task.id)
                .font(.subheadline)
                .lineLimit(1)
            if let status = task.status {
                HStack(spacing: 4) {
                    Circle()
                        .fill(taskStatusColor(status))
                        .frame(width: 6, height: 6)
                    Text(status)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func taskStatusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "completed", "success": return .green
        case "running", "in_progress": return .orange
        case "failed", "error": return .red
        default: return .secondary
        }
    }

    // MARK: - Conversations Section
    private var conversationsSection: some View {
        Section {
            ForEach(chatStore.conversations) { conv in
                conversationRow(conv)
            }
        } header: {
            HStack {
                Text("Conversazioni")
                Spacer()
                Button {
                    let newId = chatStore.createConversation()
                    selectedConversationId = newId
                } label: {
                    Image(systemName: "plus")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func conversationRow(_ conv: Conversation) -> some View {
        let isSelected = selectedConversationId == conv.id
        return Button {
            selectedConversationId = conv.id
        } label: {
            Label {
                Text(conv.title)
                    .font(.subheadline)
                    .lineLimit(1)
            } icon: {
                Image(systemName: isSelected ? "bubble.left.fill" : "bubble.left")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            }
        }
        .buttonStyle(.plain)
        .listRowBackground(
            isSelected ? Color.accentColor.opacity(0.12) : Color.clear
        )
    }

    // MARK: - Actions
    private func loadCodexTasks() {
        guard let path = codexState.status.path else { return }
        isLoadingTasks = true
        Task {
            let tasks = await CodexCloudTasks.list(codexPath: path)
            await MainActor.run {
                codexTasks = tasks
                isLoadingTasks = false
            }
        }
    }

    private func handleAddFolderSelection(result: Result<[URL], Error>) {
        guard let workspaceId = pendingAddFolderWorkspaceId else { return }
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            workspaceStore.addFolder(to: workspaceId, path: url.path(percentEncoded: false))
        case .failure: break
        }
        pendingAddFolderWorkspaceId = nil
    }

    private func handleAdHocFolderSelection(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            let paths = urls.map { $0.path(percentEncoded: false) }
            guard !paths.isEmpty else { return }
            if let convId = selectedConversationId {
                chatStore.setAdHocPaths(conversationId: convId, paths: paths)
                workspaceStore.activeWorkspaceId = nil
            } else {
                let newConvId = chatStore.createConversation(adHocFolderPaths: paths)
                selectedConversationId = newConvId
                workspaceStore.activeWorkspaceId = nil
            }
        case .failure: break
        }
    }
}

// MARK: - Rename Workspace Sheet
private struct RenameWorkspaceSheet: View {
    let workspace: Workspace
    let onDismiss: () -> Void
    @EnvironmentObject var workspaceStore: WorkspaceStore
    @State private var newName: String

    init(workspace: Workspace, onDismiss: @escaping () -> Void) {
        self.workspace = workspace
        self.onDismiss = onDismiss
        _newName = State(initialValue: workspace.name)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("Rinomina Workspace")
                .font(.title3)

            TextField("Nome", text: $newName)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: 12) {
                Button("Annulla", role: .cancel, action: onDismiss)
                Button("Salva") {
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

// MARK: - Create Workspace Sheet
private struct CreateWorkspaceSheetView: View {
    @ObservedObject var workspaceStore: WorkspaceStore
    @Binding var newWorkspaceName: String
    @Binding var showCreateWorkspace: Bool
    let onCreated: (UUID) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "folder.badge.plus")
                .font(.largeTitle)
                .foregroundStyle(Color.accentColor)

            Text("Nuovo Workspace")
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text("Nome")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Nome del workspace", text: $newWorkspaceName)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 12) {
                Button("Annulla", role: .cancel) {
                    newWorkspaceName = ""
                    showCreateWorkspace = false
                }
                Button("Crea") {
                    workspaceStore.createEmpty(name: newWorkspaceName)
                    if let ws = workspaceStore.workspaces.last {
                        onCreated(ws.id)
                    }
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
