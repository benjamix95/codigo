import SwiftUI
import CoderEngine

extension SidePanelView {
    static let excludedDirs: Set<String> = [
        ".git", ".build", ".cache", ".swiftpm", "node_modules", "DerivedData",
        ".DS_Store", "__pycache__", ".tox", ".eggs", "Pods"
    ]

    var explorerContextFingerprint: String {
        guard let context else { return "no-context" }
        let roots = context.folderPaths.joined(separator: "|")
        let excluded = context.excludedPaths.joined(separator: "|")
        return "\(context.id.uuidString)#\(roots)#\(excluded)#\(context.activeFolderPath ?? "")"
    }

    func explorerCacheKey(root: String, dir: String) -> String {
        "\(root)::\(dir)"
    }

    @MainActor
    func resetExplorerSnapshot() {
        explorerEntriesByDirectory = [:]
        loadingExplorerDirectories = []
    }

    @MainActor
    func primeExplorerRootsIfNeeded() {
        guard activeItem == .explorer, let context else { return }
        for root in context.folderPaths {
            let key = "root::\(root)"
            if expandedFolders.contains(key) {
                scheduleExplorerLoadIfNeeded(context, root: root, dir: root)
            }
        }
    }

    @MainActor
    func scheduleExplorerLoadIfNeeded(_ ctx: ProjectContext, root: String, dir: String) {
        let key = explorerCacheKey(root: root, dir: dir)
        guard explorerEntriesByDirectory[key] == nil else { return }
        guard !loadingExplorerDirectories.contains(key) else { return }
        loadingExplorerDirectories.insert(key)

        let expectedFingerprint = explorerContextFingerprint
        let excludedPaths = ctx.excludedPaths
        Task.detached(priority: .utility) {
            let entries = Self.loadExplorerEntries(
                root: root,
                dir: dir,
                excludedPaths: excludedPaths
            )
            await MainActor.run {
                guard self.explorerContextFingerprint == expectedFingerprint else { return }
                self.loadingExplorerDirectories.remove(key)
                self.explorerEntriesByDirectory[key] = entries
            }
        }
    }

    func cachedExplorerItems(root: String, dir: String) -> [ExplorerEntry] {
        explorerEntriesByDirectory[explorerCacheKey(root: root, dir: dir)] ?? []
    }

    func isExplorerDirectoryLoading(root: String, dir: String) -> Bool {
        loadingExplorerDirectories.contains(explorerCacheKey(root: root, dir: dir))
    }

    static func loadExplorerEntries(
        root: String,
        dir: String,
        excludedPaths: [String]
    ) -> [ExplorerEntry] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { return [] }
        var entries: [ExplorerEntry] = []
        entries.reserveCapacity(names.count)

        for name in names {
            if name.hasPrefix(".") && name != ".env" { continue }
            if Self.excludedDirs.contains(name) { continue }

            let full = (dir as NSString).appendingPathComponent(name)
            let rel = full.replacingOccurrences(of: root + "/", with: "")
            let isExcluded = excludedPaths.contains { rel.hasPrefix($0) || full.hasPrefix($0) }
            if isExcluded { continue }

            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: full, isDirectory: &isDir)
            entries.append(ExplorerEntry(name: name, fullPath: full, isDirectory: isDir.boolValue))
        }

        entries.sort {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory && !$1.isDirectory }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        return entries
    }

    func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        return isDir.boolValue
    }

    func toggleExpandedState(_ key: String) {
        if expandedFolders.contains(key) { expandedFolders.remove(key) } else { expandedFolders.insert(key) }
    }

    func fileIcon(for name: String, isDirectory: Bool, expanded: Bool) -> String {
        if isDirectory { return expanded ? "chevron.down" : "chevron.right" }
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

    func fileIconColor(for name: String) -> Color {
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
}
