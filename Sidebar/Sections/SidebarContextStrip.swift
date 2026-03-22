import SwiftUI
import AppKit
import CoderEngine

// MARK: - Context Strip

/// Compact always-visible context strip pinned above the footer.
/// Replaces the old full-size SidebarContextSection with a minimal
/// Cursor/VS Code-inspired design: folder icon + name + paths + menu.
extension SidebarView {

    var contextStrip: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thin separator
            Rectangle()
                .fill(DesignSystem.Colors.borderSubtle)
                .frame(height: 0.5)

            if let context = currentContext {
                contextStripContent(context)
            } else {
                contextStripEmpty
            }
        }
    }

    // MARK: - Active Context

    private func contextStripContent(_ context: ProjectContext) -> some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "folder.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.accentColor.opacity(0.7))

            VStack(alignment: .leading, spacing: 1) {
                Text(context.name)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)

                if !context.folderPaths.isEmpty {
                    Text(context.folderPaths
                        .map { ($0 as NSString).lastPathComponent }
                        .joined(separator: " \u{00B7} "))
                        .font(.system(size: 9.5))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            contextStripMenu(context)
        }
        .padding(.vertical, DesignSystem.Spacing.sm)
    }

    // MARK: - Context Menu

    private func contextStripMenu(_ context: ProjectContext) -> some View {
        Menu {
            // Switch context
            if filteredContexts.count > 1 {
                Menu("Switch Context") {
                    ForEach(filteredContexts) { ctx in
                        Button {
                            attachConversation(to: ctx.id)
                        } label: {
                            Label(ctx.name, systemImage: "folder")
                        }
                    }
                }
                Divider()
            }

            Button {
                isSelectingProjectFolders = true
            } label: {
                Label("Open Project", systemImage: "folder.badge.plus")
            }

            Button {
                pendingAddFolderContextId = context.id
                isSelectingAddFolder = true
            } label: {
                Label("Add Folder", systemImage: "plus.rectangle.on.folder")
            }

            // Scope mode
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

            // Multi-folder: switch active folder
            if context.folderPaths.count > 1 {
                Divider()
                Menu("Active Folder") {
                    ForEach(context.folderPaths, id: \.self) { folder in
                        Button {
                            projectContextStore.setActiveRoot(contextId: context.id, rootPath: folder)
                            let scope = context.folderPaths.count > 1 ? folder : nil
                            chatStore.setContextFolder(conversationId: selectedConversationId, folderPath: scope)
                            workspaceStore.syncActiveWorkspace(
                                with: projectContextStore.context(id: context.id)
                            )
                        } label: {
                            HStack {
                                Text((folder as NSString).lastPathComponent)
                                if context.activeFolderPath == folder {
                                    Image(systemName: "checkmark")
                                }
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
        Button {
            isSelectingProjectFolders = true
        } label: {
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
