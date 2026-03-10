import SwiftUI
import AppKit
import CoderEngine

extension SidebarView {
    var contextSection: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
            // Section header — slim, uppercase
            HStack(spacing: DesignSystem.Spacing.xs) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.accentColor.opacity(0.6))

                Text("Context")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.5)

                Spacer()

                // Scope mode selector
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
                    HStack(spacing: 3) {
                        Text((ContextScopeMode(rawValue: contextScopeModeRaw) ?? .auto).label)
                            .font(.system(size: 9.5, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .semibold))
                    }
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.white.opacity(0.04))
                    )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help((ContextScopeMode(rawValue: contextScopeModeRaw) ?? .auto).helpText)

                // Context switcher
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
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Switch context")
            }

            // Active context card
            if let context = currentContext {
                contextCard(context)
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

    // MARK: - Context Card

    private func contextCard(_ context: ProjectContext) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            HStack(spacing: DesignSystem.Spacing.sm) {
                // Folder icon with accent tint
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor.opacity(0.1))
                        .frame(width: 26, height: 26)
                    Image(systemName: "folder.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.accentColor.opacity(0.7))
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(context.name)
                        .font(.system(size: 11.5, weight: .semibold))
                        .lineLimit(1)
                    Text(context.activeFolderPath.map { ($0 as NSString).lastPathComponent } ?? "No folder")
                        .font(.system(size: 10))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                        .lineLimit(1)
                }

                Spacer()

                // Action buttons
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Button {
                        pendingAddFolderContextId = context.id
                        isSelectingAddFolder = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                            .frame(width: 20, height: 20)
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
                            .frame(width: 20, height: 20)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
            }
            .padding(DesignSystem.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                    .fill(Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                            .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                    )
            )

            // Multi-folder list (if more than 1 folder)
            if context.folderPaths.isEmpty {
                Text("No folders in context")
                    .font(.system(size: 10.5))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                    .padding(.leading, 4)
            } else if context.folderPaths.count > 1 {
                contextFolderList(context)
            }
        }
    }

    // MARK: - Folder List

    private func contextFolderList(_ context: ProjectContext) -> some View {
        VStack(alignment: .leading, spacing: 2) {
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
                        Circle()
                            .fill(isActiveFolder ? Color.accentColor : DesignSystem.Colors.textQuaternary)
                            .frame(width: 4, height: 4)
                        Text((folder as NSString).lastPathComponent)
                            .font(.system(size: 10.5, weight: isActiveFolder ? .semibold : .regular))
                            .foregroundStyle(isActiveFolder ? .primary : DesignSystem.Colors.textSecondary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, DesignSystem.Spacing.sm)
                    .padding(.vertical, 3)
                    .background(
                        isActiveFolder
                            ? RoundedRectangle(cornerRadius: 5)
                                .fill(Color.accentColor.opacity(0.08))
                            : nil
                    )
                }
                .buttonStyle(.plain)
                .help(folder)
            }
        }
        .padding(.leading, 4)
    }
}
