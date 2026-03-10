import SwiftUI
import AppKit
import CoderEngine

extension SidebarView {
    var contextSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            // Section header with scope mode and context switcher
            HStack {
                SidebarSectionHeader("Context", icon: "folder")

                Menu {
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
                } label: {
                    Text((ContextScopeMode(rawValue: contextScopeModeRaw) ?? .auto).label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                }
                .menuStyle(.borderlessButton)
                .help((ContextScopeMode(rawValue: contextScopeModeRaw) ?? .auto).helpText)

                Menu {
                    ForEach(filteredContexts) { context in
                        Button {
                            attachConversation(to: context.id)
                        } label: {
                            Label(context.name, systemImage: "folder")
                        }
                    }
                } label: {
                    Image(systemName: "rectangle.on.rectangle")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
                .menuStyle(.borderlessButton)
                .help("Switch context")
            }

            // Active context display — flat, no card
            if let context = currentContext {
                contextInfo(context)
            } else {
                SidebarEmptyState(
                    title: "No context",
                    subtitle: "Open one or more folders as context.",
                    icon: "folder.badge.questionmark",
                    actionTitle: "Open project"
                ) {
                    isSelectingProjectFolders = true
                }
            }
        }
    }

    // MARK: - Context Info (flat, no box)

    private func contextInfo(_ context: ProjectContext) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.accentColor.opacity(0.7))

                VStack(alignment: .leading, spacing: 1) {
                    Text(context.name)
                        .font(.system(size: 11, weight: .semibold))
                    Text(context.activeFolderPath.map { ($0 as NSString).lastPathComponent } ?? "No folder")
                        .font(.system(size: 10))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                }

                Spacer()

                Button {
                    pendingAddFolderContextId = context.id
                    isSelectingAddFolder = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Add folder to context")

                Menu {
                    Button("Rename context") { contextToRename = context }
                    Divider()
                    Button(role: .destructive) { deleteContext(context) } label: { Text("Remove context") }
                    Divider()
                    Button("Close context") { clearConversationContext() }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textQuaternary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            }

            // Multi-folder list
            if context.folderPaths.isEmpty {
                Text("No folders in context")
                    .font(.system(size: 11))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                    .padding(.leading, 24)
            } else if context.folderPaths.count > 1 {
                contextFolderList(context)
            }
        }
    }

    // MARK: - Folder List

    private func contextFolderList(_ context: ProjectContext) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xxs) {
            ForEach(context.folderPaths, id: \.self) { folder in
                let isActiveFolder = context.activeFolderPath == folder
                Button {
                    projectContextStore.setActiveRoot(contextId: context.id, rootPath: folder)
                    let scope = context.folderPaths.count > 1 ? folder : nil
                    chatStore.setContextFolder(conversationId: selectedConversationId, folderPath: scope)
                    workspaceStore.syncActiveWorkspace(with: projectContextStore.context(id: context.id))
                    let rootKey = "root::\(folder)"
                    if !expandedFolders.contains(rootKey) {
                        expandedFolders.insert(rootKey)
                    }
                } label: {
                    HStack(spacing: DesignSystem.Spacing.sm - 1) {
                        Image(systemName: "folder")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(isActiveFolder ? Color.accentColor : DesignSystem.Colors.textSecondary)
                        Text((folder as NSString).lastPathComponent)
                            .font(.system(size: 11, weight: isActiveFolder ? .semibold : .regular))
                            .foregroundStyle(isActiveFolder ? .primary : DesignSystem.Colors.textSecondary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.leading, 24)
                    .padding(.vertical, DesignSystem.Spacing.xxs)
                }
                .buttonStyle(.plain)
                .help(folder)
            }
        }
    }
}
