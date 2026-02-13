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
    @State private var hoveredConversationId: UUID?
    @State private var expandedFolders: Set<String> = []
    @State private var workspaceToRename: Workspace?
    @State private var isSelectingAdHocFolders = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            sidebarHeader
            
            ScrollView {
                LazyVStack(spacing: DesignSystem.Spacing.md) {
                    // File section (menu con Apri progetto e altre azioni)
                    fileMenuSection
                    
                    // Workspace section with file browser
                    workspaceSection
                    
                    // File browser (when c'è contesto: workspace o ad-hoc)
                    if effectiveContext(for: selectedConversationId, chatStore: chatStore, workspaceStore: workspaceStore).hasContext {
                        fileBrowserSection
                    }
                    
                    // To-do section
                    todoSection
                    
                    // Codex Tasks section
                    if codexState.status.isInstalled && codexState.status.isLoggedIn {
                        codexTasksSection
                    }
                    
                    // Conversations section
                    conversationsSection
                }
                .padding(DesignSystem.Spacing.sm)
            }
        }
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
            renameWorkspaceSheet(ws)
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
    
    // MARK: - Sidebar Header
    private var sidebarHeader: some View {
        HStack {
            Text("Codigo")
                .font(DesignSystem.Typography.title3)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
            
            Spacer()
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .overlay {
            Rectangle()
                .frame(height: 0.5)
                .foregroundStyle(DesignSystem.Colors.divider)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
    
    // MARK: - Workspace Section
    private var activeWorkspaceForConversation: Workspace? {
        guard let conv = chatStore.conversation(for: selectedConversationId),
              let wsId = conv.workspaceId else { return nil }
        return workspaceStore.workspaces.first { $0.id == wsId }
    }
    
    private var workspaceSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            sectionHeader("Workspace", icon: "folder.fill") {
                Button {
                    showCreateWorkspace = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.body)
                        .foregroundStyle(DesignSystem.Colors.primary)
                }
                .buttonStyle(.plain)
                .hoverEffect(scale: 1.1)
            }
            
            if let ws = activeWorkspaceForConversation {
                workspaceMenu(ws, isActiveForConversation: true)
                
                if !ws.folderPaths.isEmpty {
                    workspaceFoldersList(ws)
                }
                
                if workspaceStore.workspaces.count > 1 {
                    otherWorkspacesList(current: ws)
                }
            } else if !workspaceStore.workspaces.isEmpty {
                ForEach(workspaceStore.workspaces) { ws in
                    workspaceRowClickable(ws)
                }
            } else {
                createWorkspaceButton
            }
        }
    }
    
    private func workspaceRowClickable(_ ws: Workspace) -> some View {
        HStack(spacing: 0) {
            Button {
                handleWorkspaceSelected(ws)
            } label: {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    ZStack {
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                            .fill(DesignSystem.Colors.textTertiary.opacity(0.1))
                            .frame(width: 24, height: 24)
                        
                        Image(systemName: "folder")
                            .font(DesignSystem.Typography.caption2)
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                    }
                    
                    Text(ws.name)
                        .font(DesignSystem.Typography.subheadline)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .lineLimit(1)
                    
                    Spacer()
                }
                .padding(.horizontal, DesignSystem.Spacing.sm)
                .padding(.vertical, DesignSystem.Spacing.sm)
                .liquidGlass(cornerRadius: DesignSystem.CornerRadius.medium)
            }
            .buttonStyle(.plain)
            .hoverEffect(scale: 1.01)

            Button {
                pendingAddFolderWorkspaceId = ws.id
                isSelectingAddFolder = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.body)
                    .foregroundStyle(DesignSystem.Colors.primary)
            }
            .buttonStyle(.plain)
            .hoverEffect(scale: 1.1)
        }
    }
    
    private func handleWorkspaceSelected(_ ws: Workspace) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            workspaceStore.activeWorkspaceId = ws.id
            if let convId = selectedConversationId {
                chatStore.setWorkspace(conversationId: convId, workspaceId: ws.id)
            } else {
                let newId = chatStore.createConversation(workspaceId: ws.id)
                selectedConversationId = newId
            }
        }
    }
    
    private func workspaceMenu(_ ws: Workspace, isActiveForConversation: Bool) -> some View {
        let isHighlighted = chatStore.conversation(for: selectedConversationId)?.workspaceId == ws.id
        return HStack(spacing: 0) {
            Menu {
                Button {
                    workspaceToRename = ws
                } label: {
                    Label("Rinomina workspace...", systemImage: "pencil")
                }
                Button {
                    showCreateWorkspace = true
                } label: {
                    Label("Crea nuovo workspace...", systemImage: "plus")
                }
            } label: {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    ZStack {
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                            .fill(DesignSystem.Colors.primary.opacity(0.15))
                            .frame(width: 24, height: 24)
                        
                        Image(systemName: "folder.fill")
                            .font(DesignSystem.Typography.caption2)
                            .foregroundStyle(DesignSystem.Colors.primary)
                    }
                    
                    Text(ws.name)
                        .font(DesignSystem.Typography.subheadlineMedium)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.down")
                        .font(DesignSystem.Typography.caption2)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                }
                .padding(.horizontal, DesignSystem.Spacing.sm)
                .padding(.vertical, DesignSystem.Spacing.sm)
                .liquidGlass(
                    cornerRadius: DesignSystem.CornerRadius.medium,
                    tint: DesignSystem.Colors.primary
                )
                .overlay {
                    if isHighlighted {
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                            .stroke(DesignSystem.Colors.primary, lineWidth: 1.5)
                    }
                }
            }
            .menuStyle(.borderlessButton)

            Button {
                pendingAddFolderWorkspaceId = ws.id
                isSelectingAddFolder = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.body)
                    .foregroundStyle(DesignSystem.Colors.primary)
            }
            .buttonStyle(.plain)
            .hoverEffect(scale: 1.1)
        }
    }
    
    private func workspaceFoldersList(_ ws: Workspace) -> some View {
        VStack(spacing: DesignSystem.Spacing.xs) {
            ForEach(ws.folderPaths, id: \.self) { path in
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Image(systemName: "folder")
                        .font(DesignSystem.Typography.caption2)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                    
                    Text((path as NSString).lastPathComponent)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Button {
                        workspaceStore.removeFolder(from: ws.id, path: path)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.error.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .hoverEffect(scale: 1.1)
                }
                .padding(.horizontal, DesignSystem.Spacing.sm)
                .padding(.vertical, DesignSystem.Spacing.xs)
            }
        }
        .padding(.top, DesignSystem.Spacing.xs)
    }
    
    private func otherWorkspacesList(current: Workspace) -> some View {
        VStack(spacing: DesignSystem.Spacing.xs) {
            ForEach(workspaceStore.workspaces) { ws in
                if ws.id != current.id {
                    otherWorkspaceRow(ws)
                }
            }
        }
        .padding(.top, DesignSystem.Spacing.xs)
    }
    
    private func otherWorkspaceRow(_ ws: Workspace) -> some View {
        let isHighlighted = chatStore.conversation(for: selectedConversationId)?.workspaceId == ws.id
        return Button {
            handleWorkspaceSelected(ws)
        } label: {
            HStack(spacing: DesignSystem.Spacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                        .fill(DesignSystem.Colors.textTertiary.opacity(0.1))
                        .frame(width: 24, height: 24)
                    
                    Image(systemName: "folder")
                        .font(DesignSystem.Typography.caption2)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                }
                
                Text(ws.name)
                    .font(DesignSystem.Typography.subheadline)
                    .foregroundStyle(isHighlighted ? DesignSystem.Colors.primary : DesignSystem.Colors.textSecondary)
                    .lineLimit(1)
                
                Spacer()
            }
            .padding(.horizontal, DesignSystem.Spacing.sm)
            .padding(.vertical, DesignSystem.Spacing.xs)
            .background {
                if isHighlighted {
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                        .fill(DesignSystem.Colors.primary.opacity(0.1))
                }
            }
        }
        .buttonStyle(.plain)
        .hoverEffect(scale: 1.01)
    }
    
    // MARK: - File Menu Section (fuori dal Workspace)
    private var fileMenuSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            sectionHeader("File", icon: "doc.text.fill")
            
            Menu {
                Button {
                    isSelectingAdHocFolders = true
                } label: {
                    Label("Apri progetto...", systemImage: "folder.badge.plus")
                }
                .help("Apri una o più cartelle senza creare un workspace")
                
                Button {
                    showCreateWorkspace = true
                } label: {
                    Label("Nuovo workspace...", systemImage: "folder.badge.gearshape")
                }
                .help("Crea un workspace nominato per raggruppare cartelle")
                
                Divider()
                
                Button {
                    clearConversationContext()
                } label: {
                    Label("Chiudi contesto", systemImage: "xmark.circle")
                }
                .help("Rimuove workspace o progetto dalla conversazione corrente")
                .disabled(!effectiveContext(for: selectedConversationId, chatStore: chatStore, workspaceStore: workspaceStore).hasContext)
            } label: {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    ZStack {
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                            .fill(DesignSystem.Colors.primary.opacity(0.15))
                            .frame(width: 24, height: 24)
                        
                        Image(systemName: "doc.text.fill")
                            .font(DesignSystem.Typography.caption2)
                            .foregroundStyle(DesignSystem.Colors.primary)
                    }
                    
                    Text("Progetto e file")
                        .font(DesignSystem.Typography.subheadlineMedium)
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.down")
                        .font(DesignSystem.Typography.caption2)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                }
                .padding(.horizontal, DesignSystem.Spacing.sm)
                .padding(.vertical, DesignSystem.Spacing.sm)
                .liquidGlass(cornerRadius: DesignSystem.CornerRadius.medium, tint: DesignSystem.Colors.primary)
            }
            .menuStyle(.borderlessButton)
        }
    }
    
    private func clearConversationContext() {
        guard let convId = selectedConversationId else { return }
        chatStore.setWorkspace(conversationId: convId, workspaceId: nil)
        chatStore.setAdHocPaths(conversationId: convId, paths: [])
        workspaceStore.activeWorkspaceId = nil
    }
    
    private var createWorkspaceButton: some View {
        Button {
            showCreateWorkspace = true
        } label: {
            HStack(spacing: DesignSystem.Spacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                        .fill(DesignSystem.Colors.textTertiary.opacity(0.1))
                        .frame(width: 24, height: 24)
                    
                    Image(systemName: "folder.badge.plus")
                        .font(DesignSystem.Typography.caption2)
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
                
                Text("Apri cartella")
                    .font(DesignSystem.Typography.subheadlineMedium)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                
                Spacer()
            }
            .padding(.horizontal, DesignSystem.Spacing.sm)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .liquidGlass(cornerRadius: DesignSystem.CornerRadius.medium)
        }
        .buttonStyle(.plain)
        .hoverEffect(scale: 1.01)
    }
    
    // MARK: - File Browser Section
    private var fileBrowserSection: some View {
        let ctx = effectiveContext(for: selectedConversationId, chatStore: chatStore, workspaceStore: workspaceStore)
        return VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            sectionHeader("Files", icon: "doc.text.fill")
            
            ForEach(ctx.folderPaths, id: \.self) { path in
                fileBrowser(for: path)
            }
        }
    }
    
    private func fileBrowser(for path: String) -> some View {
        VStack(spacing: 1) {
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: path) {
                ForEach(contents.sorted(), id: \.self) { item in
                    let itemPath = (path as NSString).appendingPathComponent(item)
                    let isDirectory = (try? FileManager.default.attributesOfItem(atPath: itemPath)[.type] as? FileAttributeType == .typeDirectory) ?? false
                    
                    fileRow(name: item, path: itemPath, isDirectory: isDirectory, depth: 0)
                }
            }
        }
        .liquidGlass(cornerRadius: DesignSystem.CornerRadius.medium)
    }
    
    private func fileRow(name: String, path: String, isDirectory: Bool, depth: Int) -> AnyView {
        let isExpanded = expandedFolders.contains(path)
        
        return AnyView(
            VStack(spacing: 0) {
                Button {
                    if isDirectory {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
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
                    HStack(spacing: DesignSystem.Spacing.sm) {
                        // Indentation
                        if depth > 0 {
                            ForEach(0..<depth, id: \.self) { _ in
                                Rectangle()
                                    .fill(Color.clear)
                                    .frame(width: DesignSystem.Spacing.md)
                            }
                        }
                        
                        // Icon
                        Image(systemName: fileIcon(for: name, isDirectory: isDirectory, isExpanded: isExpanded))
                            .font(DesignSystem.Typography.caption2)
                            .foregroundStyle(fileIconColor(for: name, isDirectory: isDirectory))
                            .frame(width: 16)
                        
                        // Name
                        Text(name)
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(openFilesStore.openFilePath == path ? DesignSystem.Colors.primary : DesignSystem.Colors.textPrimary)
                            .lineLimit(1)
                        
                        Spacer()
                    }
                    .padding(.horizontal, DesignSystem.Spacing.sm)
                    .padding(.vertical, DesignSystem.Spacing.xs)
                    .background {
                        if openFilesStore.openFilePath == path {
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                                .fill(DesignSystem.Colors.primary.opacity(0.1))
                        }
                    }
                }
                .buttonStyle(.plain)
                
                // Expanded contents
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
        if isDirectory {
            return isExpanded ? "chevron.down" : "chevron.right"
        }
        
        // File type icons
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
        if isDirectory {
            return DesignSystem.Colors.primary
        }
        
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return DesignSystem.Colors.ideColor
        case "js", "ts", "jsx", "tsx": return DesignSystem.Colors.warning
        case "py": return DesignSystem.Colors.agentColor
        case "json": return DesignSystem.Colors.textTertiary
        default: return DesignSystem.Colors.textSecondary
        }
    }
    
    // MARK: - To-do Section
    private var todoSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            sectionHeader("To-do", icon: "checklist")
            
            TodoListView(store: todoStore)
        }
    }
    
    // MARK: - Codex Tasks Section
    private var codexTasksSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            sectionHeader("Task Cloud", icon: "cloud.fill")
            
            if isLoadingTasks {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Caricamento...")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                }
                .padding(DesignSystem.Spacing.sm)
            } else if codexTasks.isEmpty {
                Button {
                    loadCodexTasks()
                } label: {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Image(systemName: "arrow.clockwise")
                            .font(DesignSystem.Typography.caption2)
                        Text("Aggiorna")
                            .font(DesignSystem.Typography.captionMedium)
                    }
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .padding(.horizontal, DesignSystem.Spacing.sm)
                    .padding(.vertical, DesignSystem.Spacing.xs)
                    .liquidGlass(cornerRadius: DesignSystem.CornerRadius.small)
                }
                .buttonStyle(.plain)
            } else {
                ForEach(codexTasks, id: \.id) { task in
                    codexTaskRow(task)
                }
                
                Button {
                    loadCodexTasks()
                } label: {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Image(systemName: "arrow.clockwise")
                            .font(DesignSystem.Typography.caption2)
                        Text("Aggiorna")
                            .font(DesignSystem.Typography.captionMedium)
                    }
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .padding(.horizontal, DesignSystem.Spacing.sm)
                    .padding(.vertical, DesignSystem.Spacing.xs)
                    .liquidGlass(cornerRadius: DesignSystem.CornerRadius.small)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private func codexTaskRow(_ task: CodexCloudTask) -> some View {
        Button {
            // TODO: open task
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title ?? task.id)
                    .font(DesignSystem.Typography.subheadlineMedium)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .lineLimit(1)
                
                if let status = task.status {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Circle()
                            .fill(taskStatusColor(status))
                            .frame(width: 5, height: 5)
                        
                        Text(status)
                            .font(DesignSystem.Typography.caption2)
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                    }
                }
            }
            .padding(DesignSystem.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(cornerRadius: DesignSystem.CornerRadius.medium)
        }
        .buttonStyle(.plain)
        .hoverEffect(scale: 1.01)
    }
    
    private func taskStatusColor(_ status: String) -> Color {
        switch status.lowercased() {
        case "completed", "success": return DesignSystem.Colors.success
        case "running", "in_progress": return DesignSystem.Colors.warning
        case "failed", "error": return DesignSystem.Colors.error
        default: return DesignSystem.Colors.textTertiary
        }
    }
    
    // MARK: - Conversations Section
    private var conversationsSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            sectionHeader("Conversazioni", icon: "bubble.left.and.bubble.right.fill") {
                Button {
                    let newId = chatStore.createConversation()
                    selectedConversationId = newId
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.body)
                        .foregroundStyle(DesignSystem.Colors.primary)
                }
                .buttonStyle(.plain)
                .hoverEffect(scale: 1.1)
            }
            
            ForEach(chatStore.conversations) { conv in
                conversationRow(conv)
            }
        }
    }
    
    private func conversationRow(_ conv: Conversation) -> some View {
        let isSelected = selectedConversationId == conv.id
        let isHovered = hoveredConversationId == conv.id
        
        return Button {
            selectedConversationId = conv.id
        } label: {
            HStack(spacing: DesignSystem.Spacing.sm) {
                ZStack {
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                        .fill(isSelected
                              ? DesignSystem.Colors.primary.opacity(0.2)
                              : DesignSystem.Colors.textTertiary.opacity(0.1))
                        .frame(width: 24, height: 24)
                    
                    Image(systemName: isSelected ? "bubble.left.fill" : "bubble.left")
                        .font(DesignSystem.Typography.caption2)
                        .foregroundStyle(isSelected
                                         ? DesignSystem.Colors.primary
                                         : DesignSystem.Colors.textTertiary)
                }
                
                Text(conv.title)
                    .font(DesignSystem.Typography.subheadlineMedium)
                    .foregroundStyle(isSelected
                                     ? DesignSystem.Colors.textPrimary
                                     : DesignSystem.Colors.textSecondary)
                    .lineLimit(1)
                
                Spacer()
            }
            .padding(.horizontal, DesignSystem.Spacing.sm)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                        .fill(DesignSystem.Colors.primary.opacity(0.1))
                        .overlay {
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                                .stroke(DesignSystem.Colors.primary.opacity(0.3), lineWidth: 0.5)
                        }
                } else if isHovered {
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                        .fill(Color.white.opacity(0.03))
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                hoveredConversationId = hovering ? conv.id : nil
            }
        }
    }
    
    // MARK: - Section Header
    private func sectionHeader(_ title: String, icon: String) -> some View {
        sectionHeader(title, icon: icon) { EmptyView() }
    }
    
    private func sectionHeader<Trailing: View>(_ title: String, icon: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            Image(systemName: icon)
                .font(DesignSystem.Typography.caption2)
                .foregroundStyle(DesignSystem.Colors.primary.opacity(0.8))
            
            Text(title)
                .font(DesignSystem.Typography.captionMedium)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
                .textCase(.uppercase)
                .tracking(0.8)
            
            Spacer()
            
            trailing()
        }
    }
    
    
    private func renameWorkspaceSheet(_ ws: Workspace) -> some View {
        RenameWorkspaceSheet(workspace: ws, onDismiss: { workspaceToRename = nil })
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
            let path = url.path(percentEncoded: false)
            workspaceStore.addFolder(to: workspaceId, path: path)
        case .failure:
            break
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
        case .failure:
            break
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
        VStack(spacing: DesignSystem.Spacing.xl) {
            Text("Rinomina Workspace")
                .font(DesignSystem.Typography.title2)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
            
            TextField("Nome", text: $newName)
                .textFieldStyle(.plain)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .padding(DesignSystem.Spacing.sm)
                .liquidGlass(cornerRadius: DesignSystem.CornerRadius.medium, tint: DesignSystem.Colors.primary)
            
            HStack(spacing: DesignSystem.Spacing.md) {
                Button("Annulla", role: .cancel, action: onDismiss)
                    .buttonStyle(SecondaryButtonStyle())
                
                Button("Salva") {
                    var updated = workspace
                    updated.name = newName.trimmingCharacters(in: .whitespaces)
                    workspaceStore.update(updated)
                    onDismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(DesignSystem.Spacing.xl)
        .frame(width: 320)
        .liquidGlass(cornerRadius: DesignSystem.CornerRadius.xl)
    }
}

// MARK: - Create Workspace Sheet
private struct CreateWorkspaceSheetView: View {
    @ObservedObject var workspaceStore: WorkspaceStore
    @Binding var newWorkspaceName: String
    @Binding var showCreateWorkspace: Bool
    let onCreated: (UUID) -> Void
    
    var body: some View {
        VStack(spacing: DesignSystem.Spacing.xl) {
            ZStack {
                Circle()
                    .fill(DesignSystem.Colors.primaryGradient)
                    .frame(width: 56, height: 56)
                    .shadow(color: DesignSystem.Colors.primary.opacity(0.3), radius: 10, x: 0, y: 4)
                
                Image(systemName: "folder.badge.plus")
                    .font(.title2)
                    .foregroundStyle(.white)
            }
            
            Text("Nuovo Workspace")
                .font(DesignSystem.Typography.title2)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
            
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text("Nome")
                    .font(DesignSystem.Typography.captionMedium)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                
                TextField("Nome del workspace", text: $newWorkspaceName)
                    .textFieldStyle(.plain)
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .padding(DesignSystem.Spacing.sm)
                    .liquidGlass(
                        cornerRadius: DesignSystem.CornerRadius.medium,
                        tint: DesignSystem.Colors.primary
                    )
            }
            
            HStack(spacing: DesignSystem.Spacing.md) {
                Button("Annulla", role: .cancel) {
                    newWorkspaceName = ""
                    showCreateWorkspace = false
                }
                .buttonStyle(SecondaryButtonStyle())
                
                Button("Crea") {
                    workspaceStore.createEmpty(name: newWorkspaceName)
                    if let ws = workspaceStore.workspaces.last {
                        onCreated(ws.id)
                    }
                    newWorkspaceName = ""
                    showCreateWorkspace = false
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(newWorkspaceName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(DesignSystem.Spacing.xl)
        .frame(width: 360)
        .liquidGlass(cornerRadius: DesignSystem.CornerRadius.xl)
    }
}
