import SwiftUI
import CoderEngine

extension SidePanelView {
    var explorerPanelContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 10) {
                if let ctx = context {
                    if ctx.folderPaths.count > 1 {
                        explorerRootTabs(ctx)
                    }
                    ForEach(ctx.folderPaths, id: \.self) { root in
                        explorerRoot(ctx, root: root)
                    }
                } else {
                    emptyExplorer
                }
            }
            .padding(10)
        }
    }

    private func explorerRootTabs(_ ctx: ProjectContext) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ctx.folderPaths, id: \.self) { root in
                    let active = ctx.activeFolderPath == root
                    Button {
                        projectContextStore.setActiveRoot(contextId: ctx.id, rootPath: root)
                        expandedFolders.insert("root::\(root)")
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: active ? "folder.fill" : "folder")
                                .font(.system(size: 10, weight: .medium))
                            Text((root as NSString).lastPathComponent)
                                .font(.system(size: 10.5, weight: active ? .semibold : .medium))
                                .lineLimit(1)
                        }
                        .foregroundStyle(active ? Color.accentColor : .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(active ? Color.accentColor.opacity(0.12) : Color.white.opacity(0.03))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
    }

    private func explorerRoot(_ ctx: ProjectContext, root: String) -> some View {
        let key = "root::\(root)"
        let expanded = expandedFolders.contains(key)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                toggleExpandedState(key)
                projectContextStore.setActiveRoot(contextId: ctx.id, rootPath: root)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 10)
                    Image(systemName: "folder.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.accentColor.opacity(0.9))
                    Text((root as NSString).lastPathComponent)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.035))
            )

            if expanded {
                AnyView(folderItems(ctx, root: root, atPath: root, depth: 1))
                    .padding(.top, 6)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(DesignSystem.Colors.backgroundPrimary.opacity(0.66))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(DesignSystem.Colors.borderSubtle, lineWidth: 0.5)
        )
    }

    private func folderItems(_ ctx: ProjectContext, root: String, atPath: String, depth: Int) -> some View {
        let items = depth > 14 ? [] : filteredItems(ctx, root: root, dir: atPath)
        return ForEach(items, id: \.fullPath) { item in
            let fullPath = item.fullPath
            let isDir = item.isDirectory
            let key = "\(root)::\(fullPath)"
            let expanded = expandedFolders.contains(key)
            let selected = openFilesStore.openFilePath == fullPath

            VStack(alignment: .leading, spacing: 0) {
                Button {
                    if isDir {
                        toggleExpandedState(key)
                    } else {
                        projectContextStore.setActiveRoot(contextId: ctx.id, rootPath: root)
                        openFilesStore.openFile(fullPath)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Spacer().frame(width: CGFloat(depth - 1) * 14 + 10)
                        Image(systemName: fileIcon(for: item.name, isDirectory: isDir, expanded: expanded))
                            .font(.system(size: isDir ? 8 : 10, weight: isDir ? .bold : .regular))
                            .foregroundStyle(isDir ? Color.secondary.opacity(0.5) : fileIconColor(for: item.name))
                        .frame(width: 12)
                        Text(item.name)
                            .font(.system(size: 12, weight: selected ? .semibold : .medium))
                            .foregroundStyle(selected ? Color.accentColor : .primary)
                            .lineLimit(1)
                        Spacer()
                        if openFilesStore.isDirty(path: fullPath) {
                            Circle().fill(DesignSystem.Colors.warning).frame(width: 6, height: 6)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(selected ? Color.accentColor.opacity(0.12) : Color.clear)
                )
                .hoverHighlight(Color.white.opacity(0.03))

                if isDir, expanded {
                    AnyView(folderItems(ctx, root: root, atPath: fullPath, depth: depth + 1))
                }
            }
        }
    }

    private var emptyExplorer: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Nessun progetto aperto")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 60)
    }
}
