import Foundation

@MainActor
final class EditorQuickOpenStore: ObservableObject {
    @Published var query = ""
    @Published private(set) var results: [EditorQuickOpenResult] = []
    @Published private(set) var isLoading = false

    private var cachedRoots: [String] = []
    private var cachedPaths: [String] = []

    func prepare(folderPaths: [String]) {
        let normalized = folderPaths.map { URL(fileURLWithPath: $0).standardizedFileURL.path }.sorted()
        guard normalized != cachedRoots else {
            applyQuery(query)
            return
        }
        cachedRoots = normalized
        isLoading = true
        Task(priority: .utility) {
            let paths = collectFiles(in: normalized)
            await MainActor.run {
                self.cachedPaths = paths
                self.isLoading = false
                self.applyQuery(self.query)
            }
        }
    }

    func applyQuery(_ newValue: String) {
        query = newValue
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = Array(cachedPaths.prefix(80)).map {
                EditorQuickOpenResult(path: $0, displayPath: EditorPathResolver.displayPath($0, roots: cachedRoots), score: 0)
            }
            return
        }
        let needle = trimmed.lowercased()
        results = cachedPaths.compactMap { path in
            let display = EditorPathResolver.displayPath(path, roots: cachedRoots)
            let haystack = display.lowercased()
            guard haystack.contains(needle) else { return nil }
            let score = haystack == needle ? 0 : abs(haystack.count - needle.count)
            return EditorQuickOpenResult(path: path, displayPath: display, score: score)
        }
        .sorted {
            ($0.score, $0.displayPath.count, $0.displayPath) < ($1.score, $1.displayPath.count, $1.displayPath)
        }
        .prefix(100)
        .map { $0 }
    }

    private func collectFiles(in roots: [String]) -> [String] {
        var output: [String] = []
        for root in roots {
            scanDirectory(root, into: &output)
        }
        return output.sorted()
    }

    private func scanDirectory(_ path: String, into output: inout [String]) {
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: path) else { return }
        for item in items where !item.hasPrefix(".") && !Self.excludedDirectories.contains(item) {
            let fullPath = (path as NSString).appendingPathComponent(item)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue {
                scanDirectory(fullPath, into: &output)
            } else {
                output.append(fullPath)
            }
        }
    }

    private static let excludedDirectories: Set<String> = [
        ".git", ".build", "node_modules", "DerivedData", "Pods"
    ]
}
