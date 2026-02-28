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

    @State private var sidebarQuery = ""
    @State private var isSelectingAddFolder = false
    @State private var pendingAddFolderWorkspaceId: UUID?
    @State private var codexTasks: [CodexCloudTask] = []
    @State private var isLoadingTasks = false
    @State private var showCreateWorkspace = false
    @State private var newWorkspaceName = ""
    @State private var workspaceToRename: Workspace?
    @State private var conversationToRename: Conversation?
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
    /// Current project/workspace context. With no thread selected, keeps activeContextId
    /// so the project doesn't "close" when all conversations are deleted.
    private var currentContext: ProjectContext? {
        let ctxId = selectedConversation?.contextId ?? projectContextStore.activeContextId
        return projectContextStore.context(id: ctxId)
    }

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

    private func groupedThreadsByFolder(from threads: [Conversation]) -> [(folder: String?, threads: [Conversation])] {
        guard let context = currentContext else { return [(nil, threads)] }
        var map: [String?: [Conversation]] = [:]
        for conv in threads {
            let key = context.folderPaths.contains(conv.contextFolderPath ?? "") ? conv.contextFolderPath : nil
            map[key, default: []].append(conv)
        }
        let orderedFolders = context.folderPaths.map(Optional.some)
        var result: [(String?, [Conversation])] = orderedFolders.compactMap { folder in
            guard let threads = map[folder], !threads.isEmpty else { return nil }
            return (folder, threads)
        }
        if let generic = map[nil], !generic.isEmpty {
            result.append((nil, generic))
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
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
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
            }

            Divider().opacity(0.4)
            taskCloudSection
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
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
        .fileImporter(isPresented: $isSelectingAddFolder, allowedContentTypes: [.folder], allowsMultipleSelection: false, onCompletion: handleAddFolderSelection)
        .sheet(item: $workspaceToRename) { ws in
            RenameWorkspaceSheet(workspace: ws, onDismiss: { workspaceToRename = nil })
                .environmentObject(workspaceStore)
        }
        .sheet(item: $conversationToRename) { conv in
            RenameConversationSheet(conversation: conv, onDismiss: { conversationToRename = nil })
                .environmentObject(chatStore)
        }
        .onAppear { projectContextStore.ensureWorkspaceContexts(workspaceStore.workspaces) }
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 6) {
            actionRow("New thread", icon: "plus.message.fill") {
                createThread(contextId: currentContext?.id)
            }
            .accessibilityLabel("Create new thread")
            actionRow("Open project", icon: "folder.badge.plus") {
                isSelectingProjectFolders = true
            }
            .accessibilityLabel("Open project folder")
            actionRow("New workspace", icon: "folder.badge.gearshape") {
                showCreateWorkspace = true
            }
            .accessibilityLabel("Create new workspace")

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                TextField("Search", text: $sidebarQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !sidebarQuery.isEmpty {
                    Button { sidebarQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
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
                Text("Context")
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
                    Image(systemName: "rectangle.on.rectangle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .help("Switch project or workspace")
            }

            if let context = currentContext {
                HStack(spacing: 8) {
                    Image(systemName: context.kind == .workspace ? "folder.fill" : "folder")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(context.name)
                            .font(.system(size: 12, weight: .semibold))
                        Text(context.activeFolderPath.map { ($0 as NSString).lastPathComponent } ?? "No folder")
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
                        .help("Add folder to workspace")
                    }
                    Menu {
                        if let ws = workspaceStore.workspaces.first(where: { $0.id == context.id }) {
                            Button("Rename workspace") { workspaceToRename = ws }
                            Divider()
                            Button(role: .destructive) { deleteWorkspace(ws) } label: { Text("Delete workspace") }
                        } else {
                            Button(role: .destructive) {
                                projectContextStore.remove(id: context.id)
                                clearConversationContext()
                            } label: { Text("Remove project") }
                        }
                        Divider()
                        Button("Close context") { clearConversationContext() }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .menuStyle(.borderlessButton)
                }
                .padding(.vertical, 2)

                if context.kind == .workspace {
                    if context.folderPaths.isEmpty {
                        Text("No folders in workspace")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 24)
                            .padding(.top, 2)
                    } else {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Workspace folders")
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
                SidebarEmptyState(title: "No context", subtitle: "Open a project or create a workspace.", actionTitle: "Open project") {
                    isSelectingProjectFolders = true
                }
            }
        }
    }

    private var threadsSection: some View {
        let threads = visibleThreads
        return VStack(alignment: .leading, spacing: 8) {
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
                .help("Favorites only")
                Button {
                    showArchived.toggle()
                } label: {
                    Image(systemName: showArchived ? "archivebox.fill" : "archivebox")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Show archived")
                Button {
                    createThread(contextId: currentContext?.id)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                if !threads.isEmpty {
                    Menu {
                        Button {
                            for conv in threads {
                                chatStore.setArchived(conversationId: conv.id, archived: true)
                            }
                        } label: {
                            Label("Archive all threads", systemImage: "archivebox")
                        }
                        Button(role: .destructive) {
                            deleteAllVisibleThreads()
                        } label: {
                            Label("Delete all threads", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .rotationEffect(.degrees(90))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .help("Actions on all threads")
                }
            }

            if let context = currentContext {
                Text("Context: \(context.name)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            } else {
                Text("Global threads")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }

            if threads.isEmpty {
                SidebarEmptyState(
                    title: "No threads",
                    subtitle: currentContext == nil ? "Open a global thread or select a context." : "Create a thread for this context.",
                    actionTitle: "New thread"
                ) {
                    createThread(contextId: currentContext?.id)
                }
            } else {
                if let context = currentContext, context.kind == .workspace {
                    ForEach(groupedThreadsByFolder(from: threads), id: \.folder) { group in
                        Text(group.folder.map { ($0 as NSString).lastPathComponent } ?? "General")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 6)
                            .padding(.top, 4)
                        ForEach(group.threads) { conv in
                            threadRow(conv)
                        }
                    }
                } else {
                    ForEach(threads) { conv in
                        threadRow(conv)
                    }
                }

                let query = sidebarQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                if !query.isEmpty {
                    let hits = chatStore.searchThreads(query: query, includeArchived: true, limit: 12)
                    if !hits.isEmpty {
                        Button {
                            askAIAboutThreadSearch(query: query, hits: hits)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                Text("Ask AI about \(hits.count) threads found")
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
    }

    private func threadRow(_ conv: Conversation) -> some View {
        let selected = selectedConversationId == conv.id
        let hasDraft = !(chatStore.draftTexts[conv.id]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        return HStack(spacing: 8) {
            if hasDraft {
                Image(systemName: "pencil.line")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.orange)
            } else if conv.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.yellow)
            } else {
                Image(systemName: selected ? "message.fill" : "message")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
            }
            Text(conv.title)
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .lineLimit(1)
            if chatStore.isTaskActive(for: conv.id) {
                ProgressView()
                    .controlSize(.mini)
            }
            Spacer()
            Text(relativeDate(conv.createdAt))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            if let context = currentContext, context.kind == .workspace, !context.folderPaths.isEmpty {
                Menu {
                    Button("General") {
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
                .help("Move to folder...")
            }
            Button {
                chatStore.setArchived(conversationId: conv.id, archived: !conv.isArchived)
            } label: {
                Image(systemName: conv.isArchived ? "archivebox.fill" : "archivebox")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help(conv.isArchived ? "Restore thread" : "Archive thread")
            Button {
                let wasSelected = selectedConversationId == conv.id
                cleanupConversationData(for: conv)
                chatStore.deleteConversation(id: conv.id)
                if wasSelected {
                    selectedConversationId = nextConversationSelectionAfterDelete(deletedConversation: conv)
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Delete thread")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(selected ? Color.white.opacity(0.08) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contextMenu {
            Button {
                conversationToRename = conv
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            Button {
                chatStore.setFavorite(conversationId: conv.id, favorite: !conv.isFavorite)
            } label: {
                Label(conv.isFavorite ? "Remove favorite" : "Add favorite", systemImage: conv.isFavorite ? "star.fill" : "star")
            }
            Button {
                chatStore.setPinned(conversationId: conv.id, pinned: !conv.isPinned)
            } label: {
                Label(conv.isPinned ? "Unpin thread" : "Pin thread", systemImage: conv.isPinned ? "pin.fill" : "pin")
            }
            Button {
                chatStore.setArchived(conversationId: conv.id, archived: !conv.isArchived)
            } label: {
                Label(conv.isArchived ? "Restore thread" : "Archive thread", systemImage: conv.isArchived ? "archivebox.fill" : "archivebox")
            }
            Divider()
            Button(role: .destructive) {
                let wasSelected = selectedConversationId == conv.id
                cleanupConversationData(for: conv)
                chatStore.deleteConversation(id: conv.id)
                if wasSelected {
                    selectedConversationId = nextConversationSelectionAfterDelete(deletedConversation: conv)
                }
            } label: {
                Label("Delete thread", systemImage: "trash")
            }
        }
        .simultaneousGesture(TapGesture().onEnded {
            selectThread(conv)
        })
    }

    private func matchesQuery(_ conv: Conversation, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return true }
        // Only match on title for the sidebar filter; full-text search across messages
        // is handled by chatStore.searchThreads() which is shown separately below the list.
        return conv.title.lowercased().contains(q)
    }

    private func askAIAboutThreadSearch(query: String, hits: [ThreadSearchHit]) {
        let prompt = chatStore.buildThreadSearchAIPrompt(query: query, hits: hits)
        NotificationCenter.default.post(
            name: Notification.Name("CoderIDE.ThreadSearchAskAI"),
            object: nil,
            userInfo: ["prompt": prompt]
        )
    }

    private func cleanupConversationData(for conversation: Conversation) {
        let roots = Set(conversation.checkpoints.flatMap { $0.gitStates.map(\.gitRootPath) })
        for root in roots {
            try? checkpointGitStore.deleteSnapshotBranch(conversationId: conversation.id, gitRoot: root)
        }
        projectContextStore.clearLastActiveConversation(conversationId: conversation.id)
    }

    private func deleteAllVisibleThreads() {
        let toDelete = visibleThreads
        let deletedIds = Set(toDelete.map(\.id))
        let wasSelectingOne = deletedIds.contains(selectedConversationId ?? UUID())
        for conv in toDelete {
            cleanupConversationData(for: conv)
            chatStore.deleteConversation(id: conv.id)
        }
        if wasSelectingOne {
            // Pick the best remaining thread in the same context, not just any thread.
            let contextId = currentContext?.id
            selectedConversationId = chatStore.conversations.first(where: {
                !$0.isArchived && $0.contextId == contextId && !deletedIds.contains($0.id)
            })?.id ?? chatStore.conversations.first(where: { !deletedIds.contains($0.id) })?.id
        }
    }

    private func nextConversationSelectionAfterDelete(deletedConversation: Conversation) -> UUID? {
        // Keep focus in the same context/folder when possible.
        if let replacement = visibleThreads.first(where: { $0.id != deletedConversation.id }) {
            return replacement.id
        }

        // Fallback: most recent non-archived thread in the same context.
        if let sameContext = chatStore.conversations.first(where: {
            !$0.isArchived
                && $0.id != deletedConversation.id
                && $0.contextId == deletedConversation.contextId
                && $0.contextFolderPath == deletedConversation.contextFolderPath
        }) {
            return sameContext.id
        }

        // Last fallback: first available thread.
        return chatStore.conversations.first?.id
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
        let items = depth > 12 ? [] : filteredDirectoryItems(context: context, root: root, directoryPath: atPath)
        return ForEach(items, id: \.self) { item in
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
                    AnyView(folderContents(context: context, root: root, atPath: fullPath, depth: depth + 1))
                }
            }
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
                Text("Loading...")
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
            ProfileSwitcherView()

            Label("Codigo", systemImage: "command")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.clear)
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsToAccounts)) { _ in
            showSettings = true
        }
    }

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "en_US")
        f.unitsStyle = .short
        return f
    }()

    private func relativeDate(_ date: Date) -> String {
        Self.relativeDateFormatter.localizedString(for: date, relativeTo: Date())
    }

    private func attachConversation(to contextId: UUID) {
        projectContextStore.activeContextId = contextId
        syncActiveWorkspaceIfNeeded(contextId: contextId)
        let folderScope = (currentContext?.kind == .workspace) ? currentContext?.activeFolderPath : nil
        // If there's a thread you worked on in this tab, show it; otherwise new thread
        if let lastId = projectContextStore.lastActiveConversationId(contextId: contextId, folderPath: folderScope),
           let lastConv = chatStore.conversation(for: lastId),
           lastConv.contextId == contextId,
           !lastConv.isArchived,
           lastConv.messages.contains(where: { $0.role == .user }) {
            selectedConversationId = lastId
        } else {
            selectedConversationId = chatStore.createConversation(contextId: contextId, contextFolderPath: folderScope)
        }
    }

    private func syncActiveWorkspaceIfNeeded(contextId: UUID?) {
        guard let contextId else { return }
        let newId: UUID? = workspaceStore.workspaces.contains(where: { $0.id == contextId }) ? contextId : nil
        guard workspaceStore.activeWorkspaceId != newId else { return }
        workspaceStore.activeWorkspaceId = newId
        workspaceStore.save()
    }

    private func clearConversationContext() {
        guard let convId = selectedConversationId else { return }
        chatStore.setContext(conversationId: convId, contextId: nil)
        projectContextStore.activeContextId = nil
    }

    private func selectThread(_ conv: Conversation) {
        selectedConversationId = conv.id
        if let contextId = conv.contextId {
            projectContextStore.activeContextId = contextId
            syncActiveWorkspaceIfNeeded(contextId: contextId)
            if conv.messages.contains(where: { $0.role == .user }) {
                projectContextStore.setLastActiveConversation(contextId: contextId, folderPath: conv.contextFolderPath, conversationId: conv.id)
            }
        }
    }

    private func createThread(contextId: UUID?) {
        let folderScope = (currentContext?.kind == .workspace) ? currentContext?.activeFolderPath : nil

        // Reuse an existing empty thread (no user messages) with the same context
        // instead of creating duplicate blank threads.
        if let existing = chatStore.conversations.first(where: {
            !$0.isArchived
            && $0.contextId == contextId
            && $0.contextFolderPath == folderScope
            && !$0.messages.contains(where: { $0.role == .user })
        }) {
            selectedConversationId = existing.id
            if let contextId {
                projectContextStore.activeContextId = contextId
                syncActiveWorkspaceIfNeeded(contextId: contextId)
            }
            return
        }

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

    private func handleAddFolderSelection(result: Result<[URL], Error>) {
        guard let workspaceId = pendingAddFolderWorkspaceId else { return }
        defer { pendingAddFolderWorkspaceId = nil }
        guard case .success(let urls) = result, let url = urls.first else { return }
        workspaceStore.addFolder(to: workspaceId, path: url.path(percentEncoded: false))
        projectContextStore.ensureWorkspaceContexts(workspaceStore.workspaces)
    }

    private static let defaultExcludedDirs: Set<String> = [
        ".git", ".build", ".cache", ".swiftpm", "node_modules", "DerivedData",
        ".DS_Store", "__pycache__", ".tox", ".eggs", "Pods"
    ]

    private func filteredDirectoryItems(context: ProjectContext, root: String, directoryPath: String) -> [String] {
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: directoryPath) else { return [] }
        return items
            .filter { !$0.hasPrefix(".") || $0 == ".env" }
            .filter { !Self.defaultExcludedDirs.contains($0) }
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

private struct RenameConversationSheet: View {
    let conversation: Conversation
    let onDismiss: () -> Void
    @EnvironmentObject var chatStore: ChatStore
    @State private var newTitle: String

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
