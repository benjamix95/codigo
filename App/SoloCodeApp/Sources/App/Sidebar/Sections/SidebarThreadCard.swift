import SwiftUI
import CoderEngine

extension SidebarView {

    // MARK: - Thread Row

    func threadRow(_ conv: Conversation, now: Date) -> some View {
        let selected = selectedConversationId == conv.id
        let renderState = threadRenderStates[conv.id] ?? .empty
        let showsWorkIndicator = renderState.isActive || renderState.isStreaming

        return VStack(alignment: .leading, spacing: 4) {
            // Row 1: stato opzionale (pin / task / bozza) + titolo + badge modalità
            HStack(spacing: 6) {
                if conv.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textSecondary.opacity(0.9))
                }
                if showsWorkIndicator {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.52)
                        .frame(width: 10, height: 10)
                } else if !conv.isPinned, renderState.hasDraft {
                    Image(systemName: "pencil.line")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.orange)
                }

                Text(conv.title)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)

                if let todoProgressLabel = renderState.todoProgressLabel {
                    Text(todoProgressLabel)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(DesignSystem.Colors.textQuaternary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }

                Spacer(minLength: 4)

                if let mode = conv.mode {
                    SidebarModeBadge(mode: mode)
                }
            }

            // Row 2: status/date + diff stats
            HStack(spacing: 6) {
                if renderState.isActive, let status = renderState.statusText, !status.isEmpty {
                    Text(status)
                        .font(.system(size: 10))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .textShimmer(active: true)
                } else if renderState.isStreaming {
                    Text("In risposta…")
                        .font(.system(size: 10))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                        .lineLimit(1)
                        .textShimmer(active: true)
                } else {
                    Text(relativeDate(conv.createdAt, relativeTo: now))
                        .font(.system(size: 10))
                        .foregroundStyle(DesignSystem.Colors.textQuaternary)
                }

                Spacer(minLength: 0)

                if renderState.metrics.hasDiffStats {
                    SidebarThreadDiffBadge(
                        linesAdded: renderState.metrics.linesAdded,
                        linesRemoved: renderState.metrics.linesRemoved
                    )
                }
            }
        }
        .padding(.horizontal, selected ? 8 : 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(threadRowBackground(selected: selected, isActive: showsWorkIndicator))
        )
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contextMenu { threadContextMenu(conv) }
        .simultaneousGesture(TapGesture().onEnded { selectConversation(conv) })
    }

    // MARK: - Row Background

    private func threadRowBackground(selected: Bool, isActive: Bool) -> Color {
        if selected { return DesignSystem.Colors.backgroundElevated }
        if isActive { return Color.accentColor.opacity(0.04) }
        return .clear
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
