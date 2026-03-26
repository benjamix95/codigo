import SwiftUI
import CoderEngine

// MARK: - Context Strip (pinned above footer)

extension SidebarView {

    var contextStrip: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()

            if let context = activeContext {
                contextStripContent(context)
            } else {
                contextStripEmpty
            }
        }
    }

    // MARK: - Active Context

    private func contextStripContent(_ context: ProjectContext) -> some View {
        VStack(alignment: .leading, spacing: 6) {

            // ── Project header ──────────────────────────
            HStack(spacing: 8) {
                Image(systemName: "externaldrive.fill.badge.checkmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.accentColor)

                Text(context.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)

                indexBadgeWithPercent

                Spacer()

                contextStripMenu(context)
            }

            // ── Folder list ─────────────────────────────
            if !context.folderPaths.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(context.folderPaths, id: \.self) { folder in
                        let isActive = context.activeFolderPath == folder
                        let name = (folder as NSString).lastPathComponent

                        FolderRow(
                            folderName: name,
                            isActive: isActive,
                            canRemove: true,
                            onTap: { switchActiveFolder(contextId: context.id, folder: folder, context: context) },
                            onRemove: { removeFolderFromContext(contextId: context.id, folder: folder) },
                            onReveal: { NSWorkspace.shared.open(URL(fileURLWithPath: folder)) }
                        )
                    }

                    addFolderButton(contextId: context.id)
                }
            }

            indexWaitBanner
        }
        .padding(12)
    }

    @ViewBuilder
    private var indexWaitBanner: some View {
        let st = workspaceStore.indexBadgeState
        if st.shouldShowWaitNotice {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "hourglass")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.orange)
                Text(
                    "Attendere: l’indicizzazione (codebase + database vettoriale) partirà a breve o è in coda. La ricerca semantica è limitata finché non è al 100%."
                )
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.orange.opacity(0.12)))
        } else if st.shouldShowErrorNotice {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.error)
                Text("Indicizzazione non riuscita. Controlla i log o riprova da Impostazioni › Codebase Index.")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(DesignSystem.Colors.error.opacity(0.1))
            )
        }
    }

    // MARK: - Index Badge (circular progress)

    private var indexBadgeWithPercent: some View {
        let state = workspaceStore.indexBadgeState
        return HStack(spacing: 5) {
            IndexCircleBadge(state: state, dimension: 13)
            if state.hasWorkspacePaths, state.indexingEnabled {
                Text(state.displayPercentText)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(sidebarIndexPercentColor(state))
                    .fixedSize()
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func sidebarIndexPercentColor(_ st: WorkspaceIndexBadgeState) -> Color {
        if st.shouldShowErrorNotice { return DesignSystem.Colors.error }
        if st.isFullyIndexed { return DesignSystem.Colors.success }
        if st.isIndexingActive { return Color.orange }
        if st.shouldShowWaitNotice { return Color.red.opacity(0.9) }
        return DesignSystem.Colors.textSecondary
    }

    // MARK: - Add Folder

    private func addFolderButton(contextId: UUID) -> some View {
        Button {
            NotificationCenter.default.post(
                name: .sidebarAddFolderToContext,
                object: nil,
                userInfo: ["contextId": contextId]
            )
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.textQuaternary)

                Text("Add Folder")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }
            .padding(.leading, 4)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Folder Actions

    private func switchActiveFolder(contextId: UUID, folder: String, context: ProjectContext) {
        projectContextStore.setActiveRoot(contextId: contextId, rootPath: folder)
        let scope = context.folderPaths.count > 1 ? folder : nil
        chatStore.setContextFolder(conversationId: selectedConversationId, folderPath: scope)
        workspaceStore.syncActiveWorkspace(with: projectContextStore.context(id: contextId))
    }

    private func removeFolderFromContext(contextId: UUID, folder: String) {
        guard var context = projectContextStore.context(id: contextId) else { return }
        context.folderPaths.removeAll { $0 == folder }
        if context.activeFolderPath == nil || context.activeFolderPath == folder {
            context.lastActiveFolderPath = context.folderPaths.first
        }
        context.updatedAt = .now
        projectContextStore.upsert(context)
        workspaceStore.syncActiveWorkspace(with: context)
        if let selectedConversationId {
            let scope = context.folderPaths.count > 1 ? context.activeFolderPath : nil
            chatStore.setContextFolder(conversationId: selectedConversationId, folderPath: scope)
        }
    }

    // MARK: - Context Menu (3-dot)

    private func contextStripMenu(_ context: ProjectContext) -> some View {
        Menu {
            if filteredContexts.count > 1 {
                Menu("Switch Context") {
                    ForEach(filteredContexts) { ctx in
                        Button { attachConversation(to: ctx.id) } label: {
                            Label(ctx.name, systemImage: "folder")
                        }
                    }
                }
                Divider()
            }

            Button { isSelectingProjectFolders = true } label: {
                Label("Open Project", systemImage: "folder.badge.plus")
            }

            Menu("Scope Mode") {
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
            }

            Divider()
            Button("Rename") { contextToRename = context }
            Button(role: .destructive) { deleteContext(context) } label: {
                Text("Remove")
            }
            Button("Close Context") { clearConversationContext() }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.textQuaternary)
                .contentShape(Circle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: - Empty Context

    private var contextStripEmpty: some View {
        Button { isSelectingProjectFolders = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.accentColor.opacity(0.6))
                Text("Open Project")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                Spacer()
            }
            .padding(12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Folder Row

private struct FolderRow: View {
    let folderName: String
    let isActive: Bool
    let canRemove: Bool
    let onTap: () -> Void
    let onRemove: () -> Void
    let onReveal: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: isActive ? "folder.fill" : "folder")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isActive ? Color.accentColor : DesignSystem.Colors.textTertiary)
                    .frame(width: 14)

                Text(folderName)
                    .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? DesignSystem.Colors.textPrimary : DesignSystem.Colors.textSecondary)
                    .lineLimit(1)

                Spacer()

                if isHovered && canRemove {
                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(DesignSystem.Colors.textQuaternary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove from workspace")
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive
                        ? Color.accentColor.opacity(0.1)
                        : (isHovered ? Color.primary.opacity(0.04) : Color.clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.12)) { isHovered = hovering }
        }
        .contextMenu {
            Button(action: onTap) { Label("Set as Active", systemImage: "checkmark.circle") }
                .disabled(isActive)
            Button(action: onReveal) { Label("Reveal in Finder", systemImage: "arrow.up.right.square") }
            if canRemove {
                Divider()
                Button(role: .destructive, action: onRemove) { Label("Remove", systemImage: "trash") }
            }
        }
    }
}
