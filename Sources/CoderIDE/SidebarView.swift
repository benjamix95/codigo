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
    @EnvironmentObject var todoStore: TodoStore

    @Binding var selectedConversationId: UUID?
    @Binding var showSettings: Bool

    @State private var sidebarQuery = ""
    @State private var isSelectingAddFolder = false
    @State private var isSelectingProjectFolders = false
    @State private var pendingAddFolderWorkspaceId: UUID?
    @State private var codexTasks: [CodexCloudTask] = []
    @State private var isLoadingTasks = false
    @State private var showCreateWorkspace = false
    @State private var newWorkspaceName = ""
    @State private var workspaceToRename: Workspace?
    @State private var expandedFolders: Set<String> = []
    @State private var showArchived = false
    @State private var favoritesOnly = false
    @AppStorage("context_scope_mode") private var contextScopeModeRaw = "auto"
    private let checkpointGitStore = ConversationCheckpointGitStore()

    private var selectedConversation: Conversation? { chatStore.conversation(for: selectedConversationId) }
    private var isIDEMode: Bool {
        if let mode = selectedConversation?.mode { return mode == .ide }
        let pid = providerRegistry.selectedProviderId
        return ProviderSupport.isIDEProvider(id: pid) && !ProviderSupport.isAgentCompatibleProvider(id: pid)
    }
    private var currentContext: ProjectContext? { projectContextStore.context(id: selectedConversation?.contextId) }

    private var orderedContexts: [ProjectContext] {
        projectContextStore.contexts.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
            return $0.updatedAt > $1.updatedAt
        }
    }

    private var filteredContexts: [ProjectContext] {
        guard !sidebarQuery.isEmpty else { return orderedContexts }
        let q = sidebarQuery.lowercased()
        return orderedContexts.filter { $0.name.lowercased().contains(q) }
    }

    private var visibleThreads: [Conversation] {
        if let contextId = currentContext?.id {
            return chatStore.conversations
                .filter { $0.contextId == contextId }
                .filter { showArchived || !$0.isArchived || $0.isFavorite }
                .filter { !favoritesOnly || $0.isFavorite }
                .filter { matchesQuery($0, query: sidebarQuery) }
                .sorted {
                    if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
                    if $0.isFavorite != $1.isFavorite { return $0.isFavorite && !$1.isFavorite }
                    return $0.createdAt > $1.createdAt
                }
        }
        return chatStore.conversations
            .filter { $0.contextId == nil }
            .filter { showArchived || !$0.isArchived || $0.isFavorite }
            .filter { !favoritesOnly || $0.isFavorite }
            .filter { matchesQuery($0, query: sidebarQuery) }
            .sorted {
                if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
                if $0.isFavorite != $1.isFavorite { return $0.isFavorite && !$1.isFavorite }
                return $0.createdAt > $1.createdAt
            }
    }

    private var groupedThreadsByFolder: [(folder: String?, threads: [Conversation])] {
        guard let context = currentContext else { return [(nil, visibleThreads)] }
        var map: [String?: [Conversation]] = [:]
        for conv in visibleThreads {
            let key = context.folderPaths.contains(conv.contextFolderPath ?? "") ? conv.contextFolderPath : nil
            map[key, default: []].append(conv)
        }
        let orderedFolders = context.folderPaths.map(Optional.some)
        var result: [(String?, [Conversation])] = orderedFolders.compactMap { folder in
            guard let threads = map[folder], !threads.isEmpty else { return nil }
            return (folder, threads.sorted { $0.createdAt > $1.createdAt })
        }
        if let generic = map[nil], !generic.isEmpty {
            result.append((nil, generic.sorted { $0.createdAt > $1.createdAt }))
        }
        return result
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                quickActions
                Divider().opacity(0.4)
                contextSection
                Divider().opacity(0.4)
                threadsSection

                if isIDEMode, let context = currentContext, !context.folderPaths.isEmpty {
                    Divider().opacity(0.4)
                    explorerSection(context: context)
                }

                Divider().opacity(0.4)
                todoSection
                Divider().opacity(0.4)
                taskCloudSection
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
        }
        .safeAreaInset(edge: .bottom) { footer }
        .sheet(isPresented: $showCreateWorkspace) {
            CreateWorkspaceSheetView(
                workspaceStore: workspaceStore,
                newWorkspaceName: $newWorkspaceName,
                showCreateWorkspace: $showCreateWorkspace,
                onCreated: { id in
                    projectContextStore.ensureWorkspaceContexts(workspaceStore.workspaces)
                    attachConversation(to: id)
                }
            )
        }
        .fileImporter(isPresented: $isSelectingProjectFolders, allowedContentTypes: [.folder], allowsMultipleSelection: true, onCompletion: handleProjectFolderSelection)
        .fileImporter(isPresented: $isSelectingAddFolder, allowedContentTypes: [.folder], allowsMultipleSelection: false, onCompletion: handleAddFolderSelection)
        .sheet(item: $workspaceToRename) { ws in
            RenameWorkspaceSheet(workspace: ws, onDismiss: { workspaceToRename = nil })
                .environmentObject(workspaceStore)
        }
        .onAppear { projectContextStore.ensureWorkspaceContexts(workspaceStore.workspaces) }
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 6) {
            actionRow("New thread", icon: "square.and.pencil") {
                createThread(contextId: currentContext?.id)
            }
            actionRow("Apri progetto", icon: "folder.badge.plus") {
                isSelectingProjectFolders = true
            }
            actionRow("Nuovo workspace", icon: "folder.badge.gearshape") {
                showCreateWorkspace = true
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                TextField("Cerca", text: $sidebarQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !sidebarQuery.isEmpty {
                    Button { sidebarQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 6)
        }
    }

    private func actionRow(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 18)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private var contextSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Contesto")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Menu {
                    ForEach(ContextScopeMode.allCases, id: \.self) { mode in
                        Button {
                            contextScopeModeRaw = mode.rawValue
                        } label: {
                            HStack {
                                Text(mode.label)
                                if (ContextScopeMode(rawValue: contextScopeModeRaw) ?? .auto) == mode {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Text((ContextScopeMode(rawValue: contextScopeModeRaw) ?? .auto).label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .help((ContextScopeMode(rawValue: contextScopeModeRaw) ?? .auto).helpText)
                Menu {
                    ForEach(filteredContexts) { context in
                        Button {
                            attachConversation(to: context.id)
                        } label: {
                            Label(context.name, systemImage: context.kind == .workspace ? "folder.fill" : "folder")
                        }
                    }
                } label: {
                    Image(systemName: "arrow.triangle.swap")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
            }

            if let context = currentContext {
                HStack(spacing: 8) {
                    Image(systemName: context.kind == .workspace ? "folder.fill" : "folder")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(context.name)
                            .font(.system(size: 12, weight: .semibold))
                        Text(context.activeFolderPath.map { ($0 as NSString).lastPathComponent } ?? "Nessuna cartella")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    if context.kind == .workspace {
                        Button {
                            pendingAddFolderWorkspaceId = context.id
                            isSelectingAddFolder = true
                        } label: {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Aggiungi cartella al workspace")
                    }
                    Menu {
                        if let ws = workspaceStore.workspaces.first(where: { $0.id == context.id }) {
                            Button("Rinomina workspace") { workspaceToRename = ws }
                            Divider()
                            Button(role: .destructive) { deleteWorkspace(ws) } label: { Text("Elimina workspace") }
                        } else {
                            Button(role: .destructive) {
                                projectContextStore.remove(id: context.id)
                                clearConversationContext()
                            } label: { Text("Rimuovi progetto") }
                        }
                        Divider()
                        Button("Chiudi contesto") { clearConversationContext() }
                    } label: {
                        Image(systemName: "ellipsis")
                            .rotationEffect(.degrees(90))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .menuStyle(.borderlessButton)
                }
                .padding(.vertical, 2)

                if context.kind == .workspace {
                    if context.folderPaths.isEmpty {
                        Text("Nessuna cartella nel workspace")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 24)
                            .padding(.top, 2)
                    } else {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Cartelle workspace")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .padding(.leading, 24)

                            ForEach(context.folderPaths, id: \.self) { folder in
                                let isActiveFolder = context.activeFolderPath == folder
                                Button {
                                    projectContextStore.setActiveRoot(contextId: context.id, rootPath: folder)
                                    chatStore.setContextFolder(conversationId: selectedConversationId, folderPath: folder)
                                    let rootKey = "root::\(folder)"
                                    if !expandedFolders.contains(rootKey) {
                                        expandedFolders.insert(rootKey)
                                    }
                                } label: {
                                    HStack(spacing: 7) {
                                        Image(systemName: "folder")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(isActiveFolder ? Color.accentColor : .secondary)
                                        Text((folder as NSString).lastPathComponent)
                                            .font(.system(size: 11, weight: isActiveFolder ? .semibold : .regular))
                                            .foregroundStyle(isActiveFolder ? .primary : .secondary)
                                            .lineLimit(1)
                                        Spacer()
                                    }
                                    .padding(.leading, 24)
                                    .padding(.vertical, 2)
                                }
                                .buttonStyle(.plain)
                                .help(folder)
                            }
                        }
                        .padding(.top, 2)
                    }
                }
            } else {
                SidebarEmptyState(title: "Nessun contesto", subtitle: "Apri un progetto o crea un workspace.", actionTitle: "Apri progetto") {
                    isSelectingProjectFolders = true
                }
            }
        }
    }

    private var threadsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Threads")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    favoritesOnly.toggle()
                } label: {
                    Image(systemName: favoritesOnly ? "star.fill" : "star")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(favoritesOnly ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
                .help("Solo preferiti")
                Button {
                    showArchived.toggle()
                } label: {
                    Image(systemName: showArchived ? "archivebox.fill" : "archivebox")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Mostra archiviati")
                Button {
                    createThread(contextId: currentContext?.id)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            if let context = currentContext {
                Text("Contesto: \(context.name)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            } else {
                Text("Thread globali")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }

            if visibleThreads.isEmpty {
                SidebarEmptyState(
                    title: "Nessun thread",
                    subtitle: currentContext == nil ? "Apri un thread globale o seleziona un contesto." : "Crea un thread per questo contesto.",
                    actionTitle: "Nuovo thread"
                ) {
                    createThread(contextId: currentContext?.id)
                }
            } else {
                if let context = currentContext, context.kind == .workspace {
                    ForEach(groupedThreadsByFolder, id: \.folder) { group in
                        Text(group.folder.map { ($0 as NSString).lastPathComponent } ?? "Generale")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 6)
                            .padding(.top, 4)
                        ForEach(group.threads) { conv in
                            threadRow(conv)
                        }
                    }
                } else {
                    ForEach(visibleThreads) { conv in
                        threadRow(conv)
                    }
                }

                let query = sidebarQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                let hits = chatStore.searchThreads(query: query, includeArchived: true, limit: 12)
                if !query.isEmpty, !hits.isEmpty {
                    Button {
                        askAIAboutThreadSearch(query: query, hits: hits)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                            Text("Chiedi AI su \(hits.count) thread trovati")
                                .lineLimit(1)
                            Spacer()
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 6)
                }
            }
        }
    }

    private func threadRow(_ conv: Conversation) -> some View {
        let selected = selectedConversationId == conv.id
        return HStack(spacing: 8) {
            Image(systemName: selected ? "bubble.left.fill" : "bubble.left")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(selected ? Color.accentColor : .secondary)
            Text(conv.title)
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .lineLimit(1)
            Spacer()
            Text(relativeDate(conv.createdAt))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            if let context = currentContext, context.kind == .workspace, !context.folderPaths.isEmpty {
                Menu {
                    Button("Generale") {
                        chatStore.setContextFolder(conversationId: conv.id, folderPath: nil)
                    }
                    Divider()
                    ForEach(context.folderPaths, id: \.self) { folder in
                        Button((folder as NSString).lastPathComponent) {
                            chatStore.setContextFolder(conversationId: conv.id, folderPath: folder)
                        }
                    }
                } label: {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .menuStyle(.borderlessButton)
                .help("Sposta in cartella…")
            }
            Button {
                chatStore.setPinned(conversationId: conv.id, pinned: !conv.isPinned)
            } label: {
                Image(systemName: conv.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(conv.isPinned ? Color.orange : Color.secondary.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help(conv.isPinned ? "Rimuovi pin" : "Pin thread")
            Button {
                chatStore.setFavorite(conversationId: conv.id, favorite: !conv.isFavorite)
            } label: {
                Image(systemName: conv.isFavorite ? "star.fill" : "star")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(conv.isFavorite ? Color.yellow : Color.secondary.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help(conv.isFavorite ? "Rimuovi preferito" : "Aggiungi preferito")
            Button {
                chatStore.setArchived(conversationId: conv.id, archived: !conv.isArchived)
            } label: {
                Image(systemName: conv.isArchived ? "archivebox.fill" : "archivebox")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help(conv.isArchived ? "Ripristina thread" : "Archivia thread")
            Button(role: .destructive) {
                let wasSelected = selectedConversationId == conv.id
                cleanupCheckpointSnapshots(for: conv)
                chatStore.deleteConversation(id: conv.id)
                if wasSelected {
                    selectedConversationId = chatStore.conversations.first?.id
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Elimina thread")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(selected ? Color.white.opacity(0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture {
            selectedConversationId = conv.id
            if let contextId = conv.contextId {
                projectContextStore.activeContextId = contextId
                syncActiveWorkspaceIfNeeded(contextId: contextId)
                if conv.messages.contains(where: { $0.role == .user }) {
                    projectContextStore.setLastActiveConversation(contextId: contextId, folderPath: conv.contextFolderPath, conversationId: conv.id)
                }
            }
        }
    }

    private func matchesQuery(_ conv: Conversation, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return true }
        if conv.title.lowercased().contains(q) { return true }
        return conv.messages.contains(where: { $0.content.lowercased().contains(q) })
    }

    private func askAIAboutThreadSearch(query: String, hits: [ThreadSearchHit]) {
        let prompt = chatStore.buildThreadSearchAIPrompt(query: query, hits: hits)
        NotificationCenter.default.post(
            name: Notification.Name("CoderIDE.ThreadSearchAskAI"),
            object: nil,
            userInfo: ["prompt": prompt]
        )
    }

    private func cleanupCheckpointSnapshots(for conversation: Conversation) {
        let roots = Set(conversation.checkpoints.flatMap { $0.gitStates.map(\.gitRootPath) })
        for root in roots {
            try? checkpointGitStore.deleteSnapshotBranch(conversationId: conversation.id, gitRoot: root)
        }
    }

    private func explorerSection(context: ProjectContext) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Explorer")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            if context.folderPaths.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(context.folderPaths, id: \.self) { root in
                            let active = context.activeFolderPath == root
                            Button((root as NSString).lastPathComponent) {
                                projectContextStore.setActiveRoot(contextId: context.id, rootPath: root)
                                expandedFolders.insert("root::\(root)")
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: active ? .semibold : .regular))
                            .foregroundStyle(active ? Color.accentColor : .secondary)
                        }
                    }
                }
            }

            ForEach(context.folderPaths, id: \.self) { root in
                explorerRootRow(context: context, root: root)
            }
        }
    }

    private func explorerRootRow(context: ProjectContext, root: String) -> some View {
        let key = "root::\(root)"
        let expanded = expandedFolders.contains(key)
        return VStack(alignment: .leading, spacing: 1) {
            Button {
                toggleFolder(key)
                projectContextStore.setActiveRoot(contextId: context.id, rootPath: root)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                    Image(systemName: "folder.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text((root as NSString).lastPathComponent)
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)

            if expanded {
                folderContents(context: context, root: root, atPath: root, depth: 1)
            }
        }
    }

    private func folderContents(context: ProjectContext, root: String, atPath: String, depth: Int) -> some View {
        let items = filteredDirectoryItems(context: context, root: root, directoryPath: atPath)
        return AnyView(
            ForEach(items, id: \.self) { item in
                let fullPath = (atPath as NSString).appendingPathComponent(item)
                let isDirectory = isDirectoryPath(fullPath)
                let key = "\(root)::\(fullPath)"
                let expanded = expandedFolders.contains(key)
                let selected = openFilesStore.openFilePath == fullPath

                VStack(alignment: .leading, spacing: 1) {
                    Button {
                        if isDirectory {
                            toggleFolder(key)
                        } else {
                            projectContextStore.setActiveRoot(contextId: context.id, rootPath: root)
                            openFilesStore.openFile(fullPath)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Spacer().frame(width: CGFloat(depth) * 10)
                            Image(systemName: iconName(for: item, isDirectory: isDirectory, expanded: expanded))
                                .font(.system(size: 10))
                                .foregroundStyle(isDirectory ? .secondary : .tertiary)
                            Text(item)
                                .font(.system(size: 11, weight: selected ? .semibold : .regular))
                                .foregroundStyle(selected ? Color.accentColor : .primary)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                    }
                    .buttonStyle(.plain)

                    if isDirectory, expanded {
                        folderContents(context: context, root: root, atPath: fullPath, depth: depth + 1)
                    }
                }
            }
        )
    }

    private var todoSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("To-do")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            TodoListView(store: todoStore)
        }
    }

    private var taskCloudSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Task Cloud")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    loadCodexTasks()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
            }

            if isLoadingTasks {
                Text("Caricamento...")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else if let first = codexTasks.first {
                Text(first.title ?? first.id)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Label("Codigo", systemImage: "command")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.clear)
    }

    private func relativeDate(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "it_IT")
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: Date())
    }

    private func attachConversation(to contextId: UUID) {
        projectContextStore.activeContextId = contextId
        syncActiveWorkspaceIfNeeded(contextId: contextId)
        let folderScope = (currentContext?.kind == .workspace) ? currentContext?.activeFolderPath : nil
        // Se c'è un thread su cui avevi lavorato in questo tab, mostralo; altrimenti nuovo thread
        if let lastId = projectContextStore.lastActiveConversationId(contextId: contextId, folderPath: folderScope),
           let lastConv = chatStore.conversation(for: lastId),
           lastConv.contextId == contextId,
           lastConv.messages.contains(where: { $0.role == .user }) {
            selectedConversationId = lastId
        } else {
            selectedConversationId = chatStore.createConversation(contextId: contextId, contextFolderPath: folderScope)
        }
    }

    private func syncActiveWorkspaceIfNeeded(contextId: UUID?) {
        guard let contextId, workspaceStore.workspaces.contains(where: { $0.id == contextId }) else { return }
        workspaceStore.activeWorkspaceId = contextId
        workspaceStore.save()
    }

    private func clearConversationContext() {
        guard let convId = selectedConversationId else { return }
        chatStore.setContext(conversationId: convId, contextId: nil)
        projectContextStore.activeContextId = nil
    }

    private func createThread(contextId: UUID?) {
        let folderScope = (currentContext?.kind == .workspace) ? currentContext?.activeFolderPath : nil
        let newId = chatStore.createConversation(contextId: contextId, contextFolderPath: folderScope)
        selectedConversationId = newId
        if let contextId {
            projectContextStore.activeContextId = contextId
            syncActiveWorkspaceIfNeeded(contextId: contextId)
        }
    }

    private func deleteWorkspace(_ ws: Workspace) {
        chatStore.clearWorkspaceReferences(workspaceId: ws.id)
        workspaceStore.delete(id: ws.id)
        projectContextStore.remove(id: ws.id)
    }

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

    private func handleProjectFolderSelection(result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        let paths = urls.map { $0.path(percentEncoded: false) }
        guard let contextId = projectContextStore.createOrReuseSingleProject(paths: paths) else { return }
        attachConversation(to: contextId)
    }

    private func handleAddFolderSelection(result: Result<[URL], Error>) {
        guard let workspaceId = pendingAddFolderWorkspaceId else { return }
        defer { pendingAddFolderWorkspaceId = nil }
        guard case .success(let urls) = result, let url = urls.first else { return }
        workspaceStore.addFolder(to: workspaceId, path: url.path(percentEncoded: false))
        projectContextStore.ensureWorkspaceContexts(workspaceStore.workspaces)
    }

    private func filteredDirectoryItems(context: ProjectContext, root: String, directoryPath: String) -> [String] {
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: directoryPath) else { return [] }
        let defaultExcluded = Set([".git", ".build", ".cache", ".swiftpm", "node_modules", "DerivedData"])
        return items
            .filter { !defaultExcluded.contains($0) }
            .filter { item in
                let fullPath = (directoryPath as NSString).appendingPathComponent(item)
                let relPath = fullPath.replacingOccurrences(of: root + "/", with: "")
                return !context.excludedPaths.contains(where: { relPath.hasPrefix($0) || fullPath.hasPrefix($0) })
            }
            .sorted()
    }

    private func isDirectoryPath(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        return isDir.boolValue
    }

    private func toggleFolder(_ key: String) {
        if expandedFolders.contains(key) { expandedFolders.remove(key) } else { expandedFolders.insert(key) }
    }

    private func iconName(for item: String, isDirectory: Bool, expanded: Bool) -> String {
        if isDirectory { return expanded ? "chevron.down" : "chevron.right" }
        let ext = (item as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "ts", "jsx", "tsx": return "curlybraces"
        case "py": return "chevron.left.forwardslash.chevron.right"
        case "md", "markdown": return "doc.text"
        case "json": return "curlybraces.square"
        default: return "doc"
        }
    }
}

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
