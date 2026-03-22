import SwiftUI
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
                threadEmptyState
            } else {
                // Pinned threads
                if !pinnedThreads.isEmpty {
                    dateSeparator("Pinned")
                    ForEach(pinnedThreads) { conv in
                        threadRow(conv, now: now)
                    }
                }

                // Date-grouped threads
                ForEach(dateGroups, id: \.group) { dateGroup in
                    dateSeparator(dateGroup.group.rawValue)
                    ForEach(dateGroup.threads) { conv in
                        threadRow(conv, now: now)
                    }
                }

                // AI search prompt
                aiSearchPrompt
            }
        }
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
                Button { favoritesOnly.toggle() } label: {
                    Image(systemName: favoritesOnly ? "star.fill" : "star")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(favoritesOnly ? .yellow : DesignSystem.Colors.textQuaternary)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .help("Favorites only")

                Button { showArchived.toggle() } label: {
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
                            Label("Archive all", systemImage: "archivebox")
                        }
                        Button(role: .destructive) {
                            deleteAllVisibleThreads()
                        } label: {
                            Label("Delete all", systemImage: "trash")
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
                }
            }
        }
        .padding(.bottom, DesignSystem.Spacing.xs)
    }

    // MARK: - Date Separator

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

    // MARK: - Empty State

    private var threadEmptyState: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(DesignSystem.Colors.textQuaternary)
            VStack(spacing: DesignSystem.Spacing.xs) {
                Text("No threads")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                Text(activeContext == nil
                    ? "Open a global thread or select a context."
                    : "Create a thread for this context.")
                    .font(.system(size: 11))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                    .multilineTextAlignment(.center)
            }
            Button("New thread") { createThread(contextId: activeContext?.id) }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.accentColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DesignSystem.Spacing.lg)
    }

    // MARK: - AI Search Prompt

    private var aiSearchPrompt: some View {
        Group {
            let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
            if q.count >= 2 {
                let hits = chatStore.searchThreads(query: q, includeArchived: true, limit: 12)
                if !hits.isEmpty {
                    Button {
                        let prompt = chatStore.buildThreadSearchAIPrompt(query: q, hits: hits)
                        NotificationCenter.default.post(
                            name: Notification.Name("CoderIDE.ThreadSearchAskAI"),
                            object: nil,
                            userInfo: ["prompt": prompt]
                        )
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
