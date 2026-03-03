import SwiftUI
import AppKit
import CoderEngine

extension SidebarView {
    var contextSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Context")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
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
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .help((ContextScopeMode(rawValue: contextScopeModeRaw) ?? .auto).helpText)
                Menu {
                    ForEach(filteredContexts) { context in
                        Button {
                            attachConversation(to: context.id)
                        } label: {
                            Label(context.name, systemImage: context.kind == .workspace ? "folder.fill" : "folder")
                        }
                    }
                } label: {
                    Image(systemName: "rectangle.on.rectangle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .help("Switch project or workspace")
            }

            if let context = currentContext {
                HStack(spacing: 8) {
                    Image(systemName: context.kind == .workspace ? "folder.fill" : "folder")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(context.name)
                            .font(.system(size: 12, weight: .semibold))
                        Text(context.activeFolderPath.map { ($0 as NSString).lastPathComponent } ?? "No folder")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    if context.kind == .workspace {
                        Button {
                            pendingAddFolderWorkspaceId = context.id
                            isSelectingAddFolder = true
                        } label: {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Add folder to workspace")
                    }
                    Menu {
                        if let ws = workspaceStore.workspaces.first(where: { $0.id == context.id }) {
                            Button("Rename workspace") { workspaceToRename = ws }
                            Divider()
                            Button(role: .destructive) { deleteWorkspace(ws) } label: { Text("Delete workspace") }
                        } else {
                            Button(role: .destructive) {
                                projectContextStore.remove(id: context.id)
                                clearConversationContext()
                            } label: { Text("Remove project") }
                        }
                        Divider()
                        Button("Close context") { clearConversationContext() }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)

                    if context.kind == .workspace {
                        if context.folderPaths.isEmpty {
                            Text("No folders in workspace")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                                .padding(.leading, 24)
                                .padding(.top, 2)
                        } else {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Workspace folders")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                                    .padding(.leading, 24)

                                ForEach(context.folderPaths, id: \.self) { folder in
                                    let isActiveFolder = context.activeFolderPath == folder
                                    Button {
                                        projectContextStore.setActiveRoot(contextId: context.id, rootPath: folder)
                                        chatStore.setContextFolder(conversationId: selectedConversationId, folderPath: folder)
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
                }
            } else {
                SidebarEmptyState(title: "No context", subtitle: "Open a project or create a workspace.", actionTitle: "Open project") {
                    isSelectingProjectFolders = true
                }
            }
        }

}

}
