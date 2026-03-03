import SwiftUI
import AppKit
import CoderEngine

extension SidebarView {
    var threadsSection: some View {
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

    func threadRow(_ conv: Conversation) -> some View {
        let selected = selectedConversationId == conv.id
        let hasDraft = !(chatStore.draftTexts[conv.id]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let isActive = chatStore.isTaskActive(for: conv.id)
        let statusText = chatStore.taskStatusTexts[conv.id]
        return HStack(spacing: 8) {
            if isActive {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
                    .opacity(0.9)
            } else if hasDraft {
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
            VStack(alignment: .leading, spacing: 2) {
                Text(conv.title)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
                if isActive, let status = statusText, !status.isEmpty {
                    Text(status)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .textShimmer(active: true)
                }
            }
            Spacer(minLength: 4)
            if isActive {
                ProgressView()
                    .controlSize(.mini)
            }
            if !isActive {
                Text(relativeDate(conv.createdAt))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
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
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? Color.white.opacity(0.08) : (isActive ? Color.accentColor.opacity(0.04) : Color.clear))
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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

}
