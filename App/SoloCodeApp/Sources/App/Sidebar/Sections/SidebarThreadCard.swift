import SwiftUI
import CoderEngine

private struct SidebarThreadRowContent: View, Equatable {
    let title: String
    let isPinned: Bool
    let hasDraft: Bool
    let showsWorkIndicator: Bool
    let todoProgressLabel: String?
    let mode: CoderMode?
    let selected: Bool
    let secondaryText: String
    let showsSecondaryShimmer: Bool
    let metrics: SidebarThreadMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textSecondary.opacity(0.9))
                }
                if showsWorkIndicator {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.52)
                        .frame(width: 10, height: 10)
                } else if !isPinned, hasDraft {
                    Image(systemName: "pencil.line")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.orange)
                }

                Text(title)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                if let todoProgressLabel {
                    Text(todoProgressLabel)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(DesignSystem.Colors.textQuaternary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }

                Spacer(minLength: 4)

                if let mode {
                    SidebarModeBadge(mode: mode)
                }
            }

            HStack(spacing: 6) {
                Text(secondaryText)
                    .font(.system(size: 10))
                    .foregroundStyle(
                        showsSecondaryShimmer
                            ? DesignSystem.Colors.textTertiary
                            : DesignSystem.Colors.textQuaternary
                    )
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .textShimmer(active: showsSecondaryShimmer)

                Spacer(minLength: 0)

                if metrics.hasDiffStats {
                    SidebarThreadDiffBadge(
                        linesAdded: metrics.linesAdded,
                        linesRemoved: metrics.linesRemoved
                    )
                }
            }
        }
        .padding(.horizontal, selected ? 8 : 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(rowBackground(selected: selected, isActive: showsWorkIndicator))
        )
    }

    private func rowBackground(selected: Bool, isActive: Bool) -> Color {
        if selected { return DesignSystem.Colors.backgroundElevated }
        if isActive { return Color.accentColor.opacity(0.04) }
        return .clear
    }
}

extension SidebarView {

    // MARK: - Thread Row

    func threadRow(_ conv: Conversation, now: Date) -> some View {
        let selected = selectedConversationId == conv.id
        let renderState = threadRenderStates[conv.id] ?? .empty
        let showsWorkIndicator = renderState.isActive || renderState.isStreaming
        let secondaryText: String
        let showsSecondaryShimmer: Bool

        if renderState.isActive, let status = renderState.statusText, !status.isEmpty {
            secondaryText = status
            showsSecondaryShimmer = true
        } else if renderState.isStreaming {
            secondaryText = "In risposta…"
            showsSecondaryShimmer = true
        } else {
            secondaryText = relativeDate(conv.createdAt, relativeTo: now)
            showsSecondaryShimmer = false
        }

        return SidebarThreadRowContent(
            title: conv.title,
            isPinned: conv.isPinned,
            hasDraft: renderState.hasDraft,
            showsWorkIndicator: showsWorkIndicator,
            todoProgressLabel: renderState.todoProgressLabel,
            mode: conv.mode,
            selected: selected,
            secondaryText: secondaryText,
            showsSecondaryShimmer: showsSecondaryShimmer,
            metrics: renderState.metrics
        )
        .equatable()
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contextMenu { threadContextMenu(conv) }
        .simultaneousGesture(TapGesture().onEnded { selectConversation(conv) })
    }

    // MARK: - Context Menu

    @ViewBuilder
    func threadContextMenu(_ conv: Conversation) -> some View {
        Button { conversationToRename = conv } label: {
            Label("Rename", systemImage: "pencil")
        }
        Button {
            chatStore.setFavorite(conversationId: conv.id, favorite: !conv.isFavorite)
        } label: {
            Label(conv.isFavorite ? "Remove favorite" : "Add favorite",
                  systemImage: conv.isFavorite ? "star.fill" : "star")
        }
        Button {
            chatStore.setPinned(conversationId: conv.id, pinned: !conv.isPinned)
        } label: {
            Label(conv.isPinned ? "Unpin" : "Pin",
                  systemImage: conv.isPinned ? "pin.fill" : "pin")
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
                selectedConversationId = nextConversationAfterArchive(conv)
            }
        } label: {
            Label(conv.isArchived ? "Restore" : "Archive",
                  systemImage: conv.isArchived ? "archivebox.fill" : "archivebox")
        }
        Divider()
        Button(role: .destructive) {
            let wasSelected = selectedConversationId == conv.id
            cleanupConversationData(for: conv)
            let outcome = chatStore.deleteConversation(id: conv.id)
            if wasSelected {
                selectedConversationId = nextConversationAfterDelete(
                    conv, autoCreatedId: outcome.autoCreatedReplacementId
                )
            }
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}
