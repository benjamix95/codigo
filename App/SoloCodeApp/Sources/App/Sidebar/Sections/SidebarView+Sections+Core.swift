import SwiftUI
import AppKit
import CoderEngine

extension SidebarView {
    var selectedConversation: Conversation? {
        chatStore.conversation(for: selectedConversationId)
    }

    var isIDEMode: Bool {
        if let mode = selectedConversation?.mode {
            return mode == .ide
        }
        let pid = providerRegistry.selectedProviderId
        return ProviderSupport.isIDEProvider(id: pid) && !ProviderSupport.isAgentCompatibleProvider(id: pid)
    }

    /// Current project/workspace context. With no thread selected, keeps activeContextId
    /// so the project doesn't "close" when all conversations are deleted.
    var currentContext: ProjectContext? {
        let ctxId: UUID?
        if let selectedConversation {
            if let conversationContextId = selectedConversation.contextId {
                ctxId = conversationContextId
            } else {
                ctxId = preferActiveContextForGlobalThread ? projectContextStore.activeContextId : nil
            }
        } else {
            ctxId = projectContextStore.activeContextId
        }
        return projectContextStore.context(id: ctxId)
    }

    var orderedContexts: [ProjectContext] {
        projectContextStore.contexts.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned && !$1.isPinned }
            return $0.updatedAt > $1.updatedAt
        }
    }

    var filteredContexts: [ProjectContext] {
        guard !sidebarQuery.isEmpty else { return orderedContexts }
        let q = sidebarQuery.lowercased()
        return orderedContexts.filter { $0.name.lowercased().contains(q) }
    }

    var visibleThreads: [Conversation] {
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

    func groupedThreadsByFolder(from threads: [Conversation]) -> [(folder: String?, threads: [Conversation])] {
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

    var currentContextSyncFingerprint: String {
        guard let context = currentContext else { return "none" }
        let folders = context.folderPaths.joined(separator: "|")
        let exclusions = context.excludedPaths.joined(separator: "|")
        let activeRoot = context.activeFolderPath ?? ""
        return "\(context.id.uuidString)#\(folders)#\(exclusions)#\(activeRoot)"
    }

    var sidebarContent: some View {
        VStack(spacing: 0) {
            sidebarTitlebarHeader

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
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
                .padding(.vertical, 10)
            }

            Divider().opacity(0.4)
            taskCloudSection
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
        }
        .safeAreaInset(edge: .bottom) { footer }
        .fileImporter(isPresented: $isSelectingAddFolder, allowedContentTypes: [.folder], allowsMultipleSelection: false, onCompletion: handleAddFolderSelection)
        .sheet(item: $contextToRename) { context in
            RenameContextSheet(context: context, onDismiss: { contextToRename = nil })
                .environmentObject(projectContextStore)
                .environmentObject(workspaceStore)
        }
        .sheet(item: $conversationToRename) { conv in
            RenameConversationSheet(conversation: conv, onDismiss: { conversationToRename = nil })
                .environmentObject(chatStore)
        }
        .onAppear {
            scheduleSidebarWorkspaceSync(currentContextId: currentContext?.id)
        }
        .onChange(of: currentContextSyncFingerprint) { _ in
            scheduleSidebarWorkspaceSync(currentContextId: currentContext?.id)
        }
    }

    var sidebarTitlebarHeader: some View {
        Color.clear
            .frame(height: 28)
            .allowsHitTesting(false)
    }

    var quickActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            actionRow("New thread", icon: "plus.message.fill") {
                createThread(contextId: currentContext?.id)
            }
            .accessibilityLabel("Create new thread")
            actionRow("Open project", icon: "folder.badge.plus") {
                isSelectingProjectFolders = true
            }
            .accessibilityLabel("Open project folder")

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                TextField("Search", text: $sidebarQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                if !sidebarQuery.isEmpty {
                    Button { sidebarQuery = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.top, 4)
        }
    }

    func actionRow(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 16)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Spacer()
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }


}

private extension SidebarView {
    func scheduleSidebarWorkspaceSync(currentContextId: UUID?) {
        // Defer store mutations until after the current SwiftUI layout pass.
        DispatchQueue.main.async {
            projectContextStore.ensureWorkspaceContexts(workspaceStore.workspaces)
            let context = projectContextStore.context(id: currentContextId)
            workspaceStore.syncActiveWorkspace(with: context)
        }
    }
}
