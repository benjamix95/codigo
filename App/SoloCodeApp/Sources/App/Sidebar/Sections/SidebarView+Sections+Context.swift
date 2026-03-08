import SwiftUI
import AppKit
import CoderEngine

extension SidebarView {
    var contextSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Context")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
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
                        .foregroundStyle(.tertiary)
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
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .help("Switch context")
            }

            if let context = currentContext {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "folder")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(context.name)
                                .font(.system(size: 12, weight: .semibold))
                            Text(context.activeFolderPath.map { ($0 as NSString).lastPathComponent } ?? "No folder")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()

                        Button {
                            pendingAddFolderContextId = context.id
                            isSelectingAddFolder = true
                        } label: {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
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
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                    }

                    if context.folderPaths.isEmpty {
                        Text("No folders in context")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 24)
                            .padding(.top, 2)
                    } else if context.folderPaths.count > 1 {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Folders")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .padding(.leading, 24)

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
                                    HStack(spacing: 7) {
                                        Image(systemName: "folder")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(isActiveFolder ? Color.accentColor : .secondary)
                                        Text((folder as NSString).lastPathComponent)
                                            .font(.system(size: 11, weight: isActiveFolder ? .semibold : .regular))
                                            .foregroundStyle(isActiveFolder ? .primary : .secondary)
                                            .lineLimit(1)
                                        Spacer()
                                    }
                                    .padding(.leading, 24)
                                    .padding(.vertical, 2)
                                }
                                .buttonStyle(.plain)
                                .help(folder)
                            }
                        }
                        .padding(.top, 2)
                    }
                }
            } else {
                SidebarEmptyState(
                    title: "No context",
                    subtitle: "Open one or more folders as context.",
                    actionTitle: "Open project"
                ) {
                    isSelectingProjectFolders = true
                }
            }
        }
    }
}
