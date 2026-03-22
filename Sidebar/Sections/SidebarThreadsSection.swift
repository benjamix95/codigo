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

        return VStack(alignment: .leading, spacing: 0) {
            threadsSectionHeader(threads: threads)

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
                    dateSeparator("Pinned")
                    ForEach(pinnedThreads) { conv in
                        threadRow(conv, referenceDate: now, metrics: metricsFor(conv))
                    }
                }

                // Date-grouped threads
                ForEach(dateGroups, id: \.group) { dateGroup in
                    dateSeparator(dateGroup.group.rawValue)
                    ForEach(dateGroup.threads) { conv in
                        threadRow(conv, referenceDate: now, metrics: metricsFor(conv))
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
        HStack(spacing: DesignSystem.Spacing.xs) {
            Text("Threads")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.textTertiary)
                .textCase(.uppercase)
                .tracking(0.5)

            if !threads.isEmpty {
                Text("\(threads.count)")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(DesignSystem.Colors.textQuaternary)
            }

            Spacer()

            HStack(spacing: 2) {
                Button {
                    favoritesOnly.toggle()
                } label: {
                    Image(systemName: favoritesOnly ? "star.fill" : "star")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(favoritesOnly ? .yellow : DesignSystem.Colors.textQuaternary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("Favorites only")

                Button {
                    showArchived.toggle()
                } label: {
                    Image(systemName: showArchived ? "archivebox.fill" : "archivebox")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(showArchived ? Color.accentColor.opacity(0.8) : DesignSystem.Colors.textQuaternary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("Show archived")

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
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(DesignSystem.Colors.textQuaternary)
                            .frame(width: 22, height: 22)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Actions on all threads")
                }
            }
        }
        .padding(.bottom, DesignSystem.Spacing.xs)
    }

    // MARK: - Thin Date Separator

    private func dateSeparator(_ title: String) -> some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Text(title)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.textQuaternary)
            Rectangle()
                .fill(DesignSystem.Colors.borderSubtle)
                .frame(height: 0.5)
        }
        .padding(.top, DesignSystem.Spacing.sm)
        .padding(.bottom, DesignSystem.Spacing.xxs)
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
                                .font(.system(size: 10, weight: .medium))
                            Text("Ask AI about \(hits.count) threads found")
                                .font(.system(size: 10.5, weight: .medium))
                                .lineLimit(1)
                            Spacer()
                        }
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, DesignSystem.Spacing.sm)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                                .fill(Color.accentColor.opacity(0.06))
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, DesignSystem.Spacing.xs)
                }
            }
        }
    }
}
