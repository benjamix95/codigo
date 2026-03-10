import SwiftUI
import AppKit
import CoderEngine

extension SidebarView {
    var threadsSection: some View {
        let threads = visibleThreads
        let pinnedThreads = threads.filter(\.isPinned)
        let regularThreads = threads.filter { !$0.isPinned }
        let dateGroups = SidebarDateGrouper.group(regularThreads)
        let now = Date()

        return VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            // Section header with action buttons
            threadsSectionHeader(threads: threads)

            // Context label
            if let context = currentContext {
                Text("Context: \(context.name)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            } else {
                Text("Global threads")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }

            if threads.isEmpty {
                SidebarEmptyState(
                    title: "No threads",
                    subtitle: currentContext == nil
                        ? "Open a global thread or select a context."
                        : "Create a thread for this context.",
                    icon: "bubble.left.and.bubble.right",
                    actionTitle: "New thread"
                ) {
                    createThread(contextId: currentContext?.id)
                }
            } else {
                // Pinned threads
                if !pinnedThreads.isEmpty {
                    threadSubsectionTitle("Pinned")
                    ForEach(pinnedThreads) { conv in
                        threadRow(conv, referenceDate: now, metrics: metricsFor(conv))
                    }
                }

                // Date-grouped regular threads
                ForEach(dateGroups, id: \.group) { dateGroup in
                    threadSubsectionTitle(dateGroup.group.rawValue)

                    if let context = currentContext, context.folderPaths.count > 1 {
                        ForEach(groupedThreadsByFolder(from: dateGroup.threads), id: \.folder) { group in
                            Text(group.folder.map { ($0 as NSString).lastPathComponent } ?? "General")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(DesignSystem.Colors.textTertiary)
                                .padding(.horizontal, DesignSystem.Sidebar.insetXS)
                                .padding(.top, DesignSystem.Spacing.xs)
                            ForEach(group.threads) { conv in
                                threadRow(conv, referenceDate: now, metrics: metricsFor(conv))
                            }
                        }
                    } else {
                        ForEach(dateGroup.threads) { conv in
                            threadRow(conv, referenceDate: now, metrics: metricsFor(conv))
                        }
                    }
                }

                // AI search prompt
                aiSearchPrompt
            }
        }
    }

    // MARK: - Metrics

    func metricsFor(_ conv: Conversation) -> SidebarThreadMetrics {
        SidebarThreadMetrics.compute(conversation: conv, toolTraceStore: toolTraceStore)
    }

    // MARK: - Section Header

    private func threadsSectionHeader(threads: [Conversation]) -> some View {
        HStack {
            SidebarSectionHeader("Threads", icon: "bubble.left.and.text.bubble.right")

            Spacer()

            Button {
                favoritesOnly.toggle()
            } label: {
                Image(systemName: favoritesOnly ? "star.fill" : "star")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(favoritesOnly ? .yellow : DesignSystem.Colors.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Favorites only")

            Button {
                showArchived.toggle()
            } label: {
                Image(systemName: showArchived ? "archivebox.fill" : "archivebox")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Show archived")

            Button {
                createThread(contextId: currentContext?.id)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
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
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
                .menuStyle(.borderlessButton)
                .help("Actions on all threads")
            }
        }
    }

    // MARK: - AI Search Prompt

    private var aiSearchPrompt: some View {
        Group {
            let query = sidebarQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            if query.count >= 2 {
                let hits = chatStore.searchThreads(query: query, includeArchived: true, limit: 12)
                if !hits.isEmpty {
                    Button {
                        askAIAboutThreadSearch(query: query, hits: hits)
                    } label: {
                        HStack(spacing: DesignSystem.Spacing.sm - 2) {
                            Image(systemName: "sparkles")
                            Text("Ask AI about \(hits.count) threads found")
                                .lineLimit(1)
                            Spacer()
                        }
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, DesignSystem.Spacing.xs)
                }
            }
        }
    }

    // MARK: - Subsection Title

    func threadSubsectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(DesignSystem.Colors.textTertiary)
            .textCase(.uppercase)
            .tracking(0.4)
            .padding(.horizontal, DesignSystem.Sidebar.insetXS)
            .padding(.top, DesignSystem.Spacing.xs)
    }
}
