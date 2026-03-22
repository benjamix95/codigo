import SwiftUI
import AppKit
import CoderEngine

extension SidebarView {

    // MARK: - Thread Row

    func threadRow(_ conv: Conversation, referenceDate: Date, metrics: SidebarThreadMetrics) -> some View {
        let selected = selectedConversationId == conv.id
        let hasDraft = !(chatStore.draftTexts[conv.id]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let isActive = chatStore.isTaskActive(for: conv.id)
        let statusText = chatStore.taskStatusTexts[conv.id]
        let modeColor = conv.mode?.color ?? Color.accentColor

        return HStack(spacing: 0) {
            // Left accent bar for selected state
            if selected {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(modeColor)
                    .frame(width: 3)
                    .padding(.vertical, DesignSystem.Spacing.xs)
                    .padding(.trailing, DesignSystem.Spacing.xs)
            }

            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                // Row 1: Leading icon + Title + Mode badge
                HStack(spacing: DesignSystem.Spacing.xs + 2) {
                    threadLeadingIcon(conv: conv, isActive: isActive, hasDraft: hasDraft, selected: selected)

                    Text(conv.title)
                        .font(.system(size: 11, weight: selected ? .semibold : .regular))
                        .lineLimit(1)
                        .foregroundStyle(selected ? DesignSystem.Colors.textPrimary : DesignSystem.Colors.textPrimary)

                    Spacer(minLength: DesignSystem.Spacing.xs)

                    if let mode = conv.mode {
                        SidebarModeBadge(mode: mode)
                    }
                }

                // Row 2: Status / date + diff stats + message count
                HStack(spacing: DesignSystem.Spacing.sm) {
                    if isActive, let status = statusText, !status.isEmpty {
                        Text(status)
                            .font(.system(size: 10))
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .textShimmer(active: true)
                    } else {
                        Text(relativeDate(conv.createdAt, relativeTo: referenceDate))
                            .font(.system(size: 10))
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                    }

                    Spacer(minLength: 0)

                    // Diff stats badge
                    if metrics.hasDiffStats {
                        SidebarThreadDiffBadge(
                            linesAdded: metrics.linesAdded,
                            linesRemoved: metrics.linesRemoved
                        )
                    }

                    // Progress indicator
                    if isActive {
                        ProgressView()
                            .controlSize(.mini)
                    }
                }
            }
            .padding(.horizontal, selected ? DesignSystem.Spacing.sm - 2 : DesignSystem.Spacing.sm)
            .padding(.vertical, DesignSystem.Spacing.sm)
        }
        .background(threadRowBackground(selected: selected, isActive: isActive))
        .contentShape(Rectangle())
        .hoverHighlight()
        .contextMenu { threadContextMenu(conv) }
        .simultaneousGesture(TapGesture().onEnded { selectThread(conv) })
    }

    // MARK: - Leading Icon

    private func threadLeadingIcon(conv: Conversation, isActive: Bool, hasDraft: Bool, selected: Bool) -> some View {
        Group {
            if conv.isPinned {
                SidebarPinnedIconButton {
                    chatStore.setPinned(conversationId: conv.id, pinned: false)
                }
            } else if isActive {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
                    .opacity(0.9)
            } else if hasDraft {
                Image(systemName: "pencil.line")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.orange)
            } else {
                Image(systemName: selected ? "message.fill" : "message")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(selected ? Color.accentColor : DesignSystem.Colors.textSecondary)
            }
        }
        .frame(width: 14, alignment: .center)
    }

    // MARK: - Row Background

    private func threadRowBackground(selected: Bool, isActive: Bool) -> Color {
        if selected {
            return DesignSystem.Colors.backgroundElevated
        } else if isActive {
            return Color.accentColor.opacity(0.04)
        }
        return Color.clear
    }

    // MARK: - Context Menu

    @ViewBuilder
    func threadContextMenu(_ conv: Conversation) -> some View {
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
            let nextArchived = !conv.isArchived
            prepareConversationForArchive(conv)
            chatStore.setArchived(conversationId: conv.id, archived: nextArchived)
            if shouldReselectAfterArchivingThread(
                wasSelected: selectedConversationId == conv.id,
                archived: nextArchived,
                showArchived: showArchived,
                isFavorite: conv.isFavorite
            ) {
                selectedConversationId = nextConversationSelectionAfterArchive(
                    archivedConversation: conv
                )
            }
        } label: {
            Label(conv.isArchived ? "Restore thread" : "Archive thread", systemImage: conv.isArchived ? "archivebox.fill" : "archivebox")
        }
        Divider()
        Button(role: .destructive) {
            let wasSelected = selectedConversationId == conv.id
            cleanupConversationData(for: conv)
            let deletionOutcome = chatStore.deleteConversation(id: conv.id)
            if wasSelected {
                selectedConversationId = nextConversationSelectionAfterDelete(
                    deletedConversation: conv,
                    autoCreatedConversationId: deletionOutcome.autoCreatedReplacementId
                )
            }
        } label: {
            Label("Delete thread", systemImage: "trash")
        }
    }
}
