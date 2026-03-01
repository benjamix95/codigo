import SwiftUI
import CoderEngine

struct SidePanelView: View {
    let activeItem: ActivityBarItem
    let context: ProjectContext?
    @EnvironmentObject var openFilesStore: OpenFilesStore
    @EnvironmentObject var projectContextStore: ProjectContextStore
    @EnvironmentObject var gitPanelStore: GitPanelStore

    @State private var expandedFolders: Set<String> = []
    @State private var searchQuery = ""
    @State private var searchResults: [(path: String, line: Int, text: String)] = []

    var body: some View {
        VStack(spacing: 0) {
            panelHeader
            Divider().opacity(0.3)

            switch activeItem {
            case .explorer:
                explorerContent
            case .search:
                searchContent
            case .sourceControl:
                sourceControlContent
            case .settings:
                EmptyView()
            }
        }
        .frame(maxHeight: .infinity)
        .background(DesignSystem.Colors.backgroundPrimary)
        .overlay(alignment: .trailing) {
            Rectangle().fill(DesignSystem.Colors.border).frame(width: 0.5)
        }
    }

    // MARK: - Header

    private var panelHeader: some View {
        HStack(spacing: 6) {
            Text(activeItem.tooltip.uppercased())
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)
                .tracking(0.8)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Explorer

    private var explorerContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0) {
                if let ctx = context {
                    if ctx.folderPaths.count > 1 {
                        rootTabs(ctx)
                    }
                    ForEach(ctx.folderPaths, id: \.self) { root in
                        explorerRoot(ctx, root: root)
                    }
                } else {
                    emptyExplorer
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func rootTabs(_ ctx: ProjectContext) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(ctx.folderPaths, id: \.self) { root in
                    let active = ctx.activeFolderPath == root
                    Button {
                        projectContextStore.setActiveRoot(contextId: ctx.id, rootPath: root)
                        expandedFolders.insert("root::\(root)")
                    } label: {
                        Text((root as NSString).lastPathComponent)
                            .font(.system(size: 10, weight: active ? .semibold : .regular))
                            .foregroundStyle(active ? Color.accentColor : .secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(active ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
    }

    private func explorerRoot(_ ctx: ProjectContext, root: String) -> some View {
        let key = "root::\(root)"
        let expanded = expandedFolders.contains(key)
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                toggle(key)
                projectContextStore.setActiveRoot(contextId: ctx.id, rootPath: root)
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 10)
                    Image(systemName: "folder.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text((root as NSString).lastPathComponent)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                folderItems(ctx, root: root, atPath: root, depth: 1)
            }
        }
    }

    private func folderItems(_ ctx: ProjectContext, root: String, atPath: String, depth: Int) -> some View {
        let items = depth > 14 ? [] : filteredItems(ctx, root: root, dir: atPath)
        return ForEach(items, id: \.self) { item in
            let fullPath = (atPath as NSString).appendingPathComponent(item)
            let isDir = isDirectory(fullPath)
            let key = "\(root)::\(fullPath)"
            let exp = expandedFolders.contains(key)
            let selected = openFilesStore.openFilePath == fullPath

            VStack(alignment: .leading, spacing: 0) {
                Button {
                    if isDir {
                        toggle(key)
                    } else {
                        projectContextStore.setActiveRoot(contextId: ctx.id, rootPath: root)
                        openFilesStore.openFile(fullPath)
                    }
                } label: {
                    HStack(spacing: 5) {
                        Spacer().frame(width: CGFloat(depth) * 12 + 10)
                        Image(systemName: fileIcon(item, isDir: isDir, expanded: exp))
                            .font(.system(size: isDir ? 8 : 10, weight: isDir ? .bold : .regular))
                            .foregroundStyle(isDir ? Color.secondary.opacity(0.5) : fileIconColor(item))
                            .frame(width: 12)
                        Text(item)
                            .font(.system(size: 12, weight: selected ? .semibold : .regular))
                            .foregroundStyle(selected ? Color.accentColor : .primary)
                            .lineLimit(1)
                        Spacer()
                        if openFilesStore.isDirty(path: fullPath) {
                            Circle().fill(DesignSystem.Colors.warning).frame(width: 5, height: 5)
                        }
                    }
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(selected ? Color.accentColor.opacity(0.1) : .clear)

                if isDir, exp {
                    AnyView(folderItems(ctx, root: root, atPath: fullPath, depth: depth + 1))
                }
            }
        }
    }

    private var emptyExplorer: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 24, weight: .ultraLight))
                .foregroundStyle(.tertiary)
            Text("No project open")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Search

    private var searchContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                TextField("Search files...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit { performSearch() }
                if !searchQuery.isEmpty {
                    Button { searchQuery = ""; searchResults = [] } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(DesignSystem.Colors.backgroundSecondary)

            Divider().opacity(0.2)

            if searchResults.isEmpty && !searchQuery.isEmpty {
                VStack(spacing: 6) {
                    Text("No results")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(searchResults.prefix(200).enumerated()), id: \.offset) { _, result in
                            Button {
                                openFilesStore.openFile(result.path)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text((result.path as NSString).lastPathComponent)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Text("L\(result.line): \(result.text)")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Source Control

    private var sourceControlContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if gitPanelStore.isOpen {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Source Control", systemImage: "arrow.triangle.branch")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("Git panel is open on the right")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.top, 12)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 24, weight: .ultraLight))
                        .foregroundStyle(.tertiary)
                    Text("Open Git panel to view changes")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Button {
                        gitPanelStore.isOpen = true
                    } label: {
                        Text("Open Git Panel")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 60)
            }
            Spacer()
        }
    }

    // MARK: - Helpers

    private static let excludedDirs: Set<String> = [
        ".git", ".build", ".cache", ".swiftpm", "node_modules", "DerivedData",
        ".DS_Store", "__pycache__", ".tox", ".eggs", "Pods"
    ]

    private func filteredItems(_ ctx: ProjectContext, root: String, dir: String) -> [String] {
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return [] }
        return items
            .filter { !$0.hasPrefix(".") || $0 == ".env" }
            .filter { !Self.excludedDirs.contains($0) }
            .filter { item in
                let full = (dir as NSString).appendingPathComponent(item)
                let rel = full.replacingOccurrences(of: root + "/", with: "")
                return !ctx.excludedPaths.contains(where: { rel.hasPrefix($0) || full.hasPrefix($0) })
            }
            .sorted { a, b in
                let aDir = isDirectory((dir as NSString).appendingPathComponent(a))
                let bDir = isDirectory((dir as NSString).appendingPathComponent(b))
                if aDir != bDir { return aDir }
                return a.localizedCaseInsensitiveCompare(b) == .orderedAscending
            }
    }

    private func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        return isDir.boolValue
    }

    private func toggle(_ key: String) {
        if expandedFolders.contains(key) { expandedFolders.remove(key) } else { expandedFolders.insert(key) }
    }

    private func fileIcon(_ name: String, isDir: Bool, expanded: Bool) -> String {
        if isDir { return expanded ? "chevron.down" : "chevron.right" }
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "ts", "jsx", "tsx": return "curlybraces"
        case "py": return "chevron.left.forwardslash.chevron.right"
        case "json": return "curlybraces.square"
        case "md", "markdown": return "doc.text"
        case "html", "htm": return "globe"
        case "css", "scss": return "paintbrush"
        case "rs": return "gearshape.2"
        case "go": return "arrow.right.arrow.left"
        case "rb": return "diamond"
        case "yml", "yaml": return "list.bullet.indent"
        case "sh", "zsh", "bash": return "terminal"
        case "png", "jpg", "jpeg", "svg", "gif", "webp": return "photo"
        default: return "doc"
        }
    }

    private func fileIconColor(_ name: String) -> Color {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return .orange
        case "js", "jsx": return .yellow
        case "ts", "tsx": return .blue
        case "py": return .green
        case "json": return .yellow.opacity(0.7)
        case "md", "markdown": return .cyan
        case "html", "htm": return .orange.opacity(0.7)
        case "css", "scss": return .purple
        case "rs": return .orange.opacity(0.8)
        case "go": return .cyan
        case "rb": return .red
        default: return .secondary
        }
    }

    private func performSearch() {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, let ctx = context else { searchResults = []; return }

        Task {
            var results: [(path: String, line: Int, text: String)] = []
            for root in ctx.folderPaths {
                await searchInDirectory(root, query: q, results: &results, maxResults: 200)
            }
            await MainActor.run { searchResults = results }
        }
    }

    private func searchInDirectory(
        _ dir: String,
        query: String,
        results: inout [(path: String, line: Int, text: String)],
        maxResults: Int
    ) async {
        guard results.count < maxResults else { return }
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return }
        let filtered = items.filter { !$0.hasPrefix(".") && !Self.excludedDirs.contains($0) }

        for item in filtered {
            guard results.count < maxResults else { return }
            let path = (dir as NSString).appendingPathComponent(item)
            if isDirectory(path) {
                await searchInDirectory(path, query: query, results: &results, maxResults: maxResults)
            } else {
                guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
                let lines = content.components(separatedBy: .newlines)
                for (i, line) in lines.enumerated() {
                    guard results.count < maxResults else { break }
                    if line.localizedCaseInsensitiveContains(query) {
                        results.append((path: path, line: i + 1, text: line.trimmingCharacters(in: .whitespaces)))
                    }
                }
            }
        }
    }
}
