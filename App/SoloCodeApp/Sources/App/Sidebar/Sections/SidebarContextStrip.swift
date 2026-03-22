import SwiftUI
import CoderEngine

/// Always-visible context area pinned above the footer.
/// Shows the context name, an expandable list of folders (active one highlighted),
/// and a menu for context-level actions.
extension SidebarView {

    var contextStrip: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(DesignSystem.Colors.borderSubtle)
                .frame(height: 0.5)

            if let context = activeContext {
                contextStripContent(context)
            } else {
                contextStripEmpty
            }
        }
    }

    // MARK: - Active Context Header + Folder List

    private func contextStripContent(_ context: ProjectContext) -> some View {
        VStack(alignment: .leading, spacing: 0) {

            // Header row: icon + name + menu
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.accentColor.opacity(0.7))

                Text(context.name)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)

                Spacer()

                contextStripMenu(context)
            }
            .padding(.top, DesignSystem.Spacing.sm)
            .padding(.bottom, context.folderPaths.isEmpty ? DesignSystem.Spacing.sm : DesignSystem.Spacing.xs)

            // Folder list
            if !context.folderPaths.isEmpty {
                contextFolderList(context)
                    .padding(.bottom, DesignSystem.Spacing.sm)
            }
        }
    }

    // MARK: - Folder List (each folder is tappable)

    private func contextFolderList(_ context: ProjectContext) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(context.folderPaths, id: \.self) { folder in
                let isActive = context.activeFolderPath == folder
                let folderName = (folder as NSString).lastPathComponent

                Button {
                    switchActiveFolder(contextId: context.id, folder: folder, context: context)
                } label: {
                    HStack(spacing: DesignSystem.Spacing.xs + 2) {
                        // Active indicator dot
                        Circle()
                            .fill(isActive ? Color.accentColor : Color.clear)
                            .frame(width: 5, height: 5)

                        Image(systemName: isActive ? "folder.fill" : "folder")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(isActive ? Color.accentColor : DesignSystem.Colors.textTertiary)
                            .frame(width: 12)

                        Text(folderName)
                            .font(.system(size: 10.5, weight: isActive ? .semibold : .regular))
                            .foregroundStyle(isActive ? DesignSystem.Colors.textPrimary : DesignSystem.Colors.textSecondary)
                            .lineLimit(1)

                        Spacer()

                        if isActive {
                            Text("active")
                                .font(.system(size: 8, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.accentColor.opacity(0.7))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(
                                    Capsule().fill(Color.accentColor.opacity(0.1))
                                )
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.sm)
                    .padding(.vertical, DesignSystem.Spacing.xs)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.Sidebar.rowRadius)
                            .fill(isActive ? Color.accentColor.opacity(0.08) : Color.clear)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button {
                        switchActiveFolder(contextId: context.id, folder: folder, context: context)
                    } label: {
                        Label("Set as Active", systemImage: "checkmark.circle")
                    }
                    .disabled(isActive)

                    Button {
                        NSWorkspace.shared.open(URL(fileURLWithPath: folder))
                    } label: {
                        Label("Reveal in Finder", systemImage: "arrow.up.right.square")
                    }

                    if context.folderPaths.count > 1 {
                        Divider()
                        Button(role: .destructive) {
                            removeFolderFromContext(contextId: context.id, folder: folder)
                        } label: {
                            Label("Remove Folder", systemImage: "minus.circle")
                        }
                    }
                }
            }

            // Add folder button inline
            Button {
                NotificationCenter.default.post(
                    name: .sidebarAddFolderToContext,
                    object: nil,
                    userInfo: ["contextId": context.id]
                )
            } label: {
                HStack(spacing: DesignSystem.Spacing.xs + 2) {
                    Circle()
                        .fill(Color.clear)
                        .frame(width: 5, height: 5)

                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textQuaternary)
                        .frame(width: 12)

                    Text("Add Folder")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)

                    Spacer()
                }
                .padding(.horizontal, DesignSystem.Spacing.sm)
                .padding(.vertical, DesignSystem.Spacing.xs)
            }
            .buttonStyle(.plain)
        }
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
            Image(systemName: "ellipsis")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.textQuaternary)
                .frame(width: 20, height: 20)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // MARK: - Empty Context

    private var contextStripEmpty: some View {
        Button { isSelectingProjectFolders = true } label: {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 11))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                Text("Open Project")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                Spacer()
            }
            .padding(.vertical, DesignSystem.Spacing.sm)
        }
        .buttonStyle(.plain)
    }
}
