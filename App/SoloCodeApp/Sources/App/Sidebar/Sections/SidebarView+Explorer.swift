import SwiftUI
import AppKit

extension SidebarView {
    func explorerSection(context: ProjectContext) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Explorer")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if context.folderPaths.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(context.folderPaths, id: \.self) { root in
                            let active = context.activeFolderPath == root
                            Button((root as NSString).lastPathComponent) {
                                projectContextStore.setActiveRoot(contextId: context.id, rootPath: root)
                                expandedFolders.insert("root::\(root)")
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 10, weight: active ? .semibold : .regular))
                            .foregroundStyle(active ? Color.accentColor : .secondary)
                        }
                    }
                }
            }

            ForEach(context.folderPaths, id: \.self) { root in
                explorerRootRow(context: context, root: root)
            }
        }
    }

    func explorerRootRow(context: ProjectContext, root: String) -> some View {
        let key = "root::\(root)"
        let expanded = expandedFolders.contains(key)
        return VStack(alignment: .leading, spacing: 1) {
            Button {
                toggleFolder(key)
                projectContextStore.setActiveRoot(contextId: context.id, rootPath: root)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                    Image(systemName: "folder.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text((root as NSString).lastPathComponent)
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)

            if expanded {
                folderContents(context: context, root: root, atPath: root, depth: 1)
            }
        }
    }

    func folderContents(context: ProjectContext, root: String, atPath: String, depth: Int) -> some View {
        let items = depth > 12 ? [] : filteredDirectoryItems(context: context, root: root, directoryPath: atPath)
        return ForEach(items, id: \.self) { item in
            let fullPath = (atPath as NSString).appendingPathComponent(item)
            let isDirectory = isDirectoryPath(fullPath)
            let key = "\(root)::\(fullPath)"
            let expanded = expandedFolders.contains(key)
            let selected = openFilesStore.openFilePath == fullPath

            VStack(alignment: .leading, spacing: 1) {
                Button {
                    if isDirectory {
                        toggleFolder(key)
                    } else {
                        projectContextStore.setActiveRoot(contextId: context.id, rootPath: root)
                        openFilesStore.openFile(fullPath)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Spacer().frame(width: CGFloat(depth) * 10)
                        Image(systemName: iconName(for: item, isDirectory: isDirectory, expanded: expanded))
                            .font(.system(size: 10))
                            .foregroundStyle(isDirectory ? .secondary : .tertiary)
                        Text(item)
                            .font(.system(size: 11, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? Color.accentColor : .primary)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                }
                .buttonStyle(.plain)

                if isDirectory, expanded {
                    AnyView(folderContents(context: context, root: root, atPath: fullPath, depth: depth + 1))
                }
            }
        }
    }

    static let defaultExcludedDirs: Set<String> = [
        ".git", ".build", ".cache", ".swiftpm", "node_modules", "DerivedData",
        ".DS_Store", "__pycache__", ".tox", ".eggs", "Pods"
    ]

    func filteredDirectoryItems(context: ProjectContext, root: String, directoryPath: String) -> [String] {
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: directoryPath) else { return [] }
        return items
            .filter { !$0.hasPrefix(".") || $0 == ".env" }
            .filter { !Self.defaultExcludedDirs.contains($0) }
            .filter { item in
                let fullPath = (directoryPath as NSString).appendingPathComponent(item)
                let relPath = fullPath.replacingOccurrences(of: root + "/", with: "")
                return !context.excludedPaths.contains(where: { relPath.hasPrefix($0) || fullPath.hasPrefix($0) })
            }
            .sorted()
    }

    func isDirectoryPath(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        return isDir.boolValue
    }

    func toggleFolder(_ key: String) {
        if expandedFolders.contains(key) { expandedFolders.remove(key) } else { expandedFolders.insert(key) }
    }

    func iconName(for item: String, isDirectory: Bool, expanded: Bool) -> String {
        if isDirectory { return expanded ? "chevron.down" : "chevron.right" }
        let ext = (item as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "ts", "jsx", "tsx": return "curlybraces"
        case "py": return "chevron.left.forwardslash.chevron.right"
        case "md", "markdown": return "doc.text"
        case "json": return "curlybraces.square"
        default: return "doc"
        }
    }
}
