import Foundation

extension CodebaseIndex {

    func isExcluded(_ name: String, relativePath: String = "") -> Bool {
        for pattern in excludedPaths {
            // Exact name match (existing behavior)
            if name == pattern { return true }
            // Path prefix match: "Sources/Generated" matches files under that path
            if !relativePath.isEmpty && !pattern.contains("*") {
                if relativePath == pattern || relativePath.hasPrefix(pattern + "/") { return true }
            }
            // Glob pattern match
            if pattern.contains("*") {
                let pathToCheck = relativePath.isEmpty ? name : relativePath
                if matchGlob(pattern: pattern.lowercased(), path: pathToCheck.lowercased()) { return true }
            }
        }
        return false
    }

    // MARK: - Private: Tree String Builder

    func buildTreeString(
        node: FileNode,
        prefix: String,
        isLast: Bool,
        currentDepth: Int,
        maxDepth: Int,
        maxFiles: Int,
        includeHidden: Bool
    ) -> String {
        guard currentDepth < maxDepth else { return "" }

        var result = ""
        let sortedChildren = node.children.sorted { a, b in
            if a.kind != b.kind { return a.kind == .directory }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }

        let filtered =
            includeHidden ? sortedChildren : sortedChildren.filter { !$0.name.hasPrefix(".") }
        let shown = Array(filtered.prefix(maxFiles))
        let truncated = filtered.count > maxFiles

        for (i, child) in shown.enumerated() {
            let isChildLast = (i == shown.count - 1) && !truncated
            let connector = isChildLast ? "└── " : "├── "
            let childPrefix = isChildLast ? "    " : "│   "

            if child.kind == .directory {
                let fileCount = child.totalFileCount
                result += "\(prefix)\(connector)\(child.name)/ (\(fileCount) files)\n"
                result += buildTreeString(
                    node: child,
                    prefix: prefix + childPrefix,
                    isLast: isChildLast,
                    currentDepth: currentDepth + 1,
                    maxDepth: maxDepth,
                    maxFiles: maxFiles,
                    includeHidden: includeHidden
                )
            } else {
                let sizeStr = ByteCountFormatter.string(
                    fromByteCount: Int64(child.size), countStyle: .file)
                result += "\(prefix)\(connector)\(child.name) (\(sizeStr))\n"
            }
        }

        if truncated {
            result += "\(prefix)└── ... (\(filtered.count - maxFiles) more)\n"
        }

        return result
    }

    // MARK: - Private: Gitignore & File Exclusion

    /// Parse .gitignore from the workspace root
    func loadGitignoreRules(for rootURL: URL) {
        gitignoreRules = []
        let gitignorePath = rootURL.appendingPathComponent(".gitignore").path
        guard let content = try? String(contentsOfFile: gitignorePath, encoding: .utf8) else { return }

        for line in content.components(separatedBy: .newlines) {
            var rule = line.trimmingCharacters(in: .whitespaces)
            if rule.isEmpty || rule.hasPrefix("#") { continue }

            let isNegation = rule.hasPrefix("!")
            if isNegation { rule = String(rule.dropFirst()) }

            let isDirectoryOnly = rule.hasSuffix("/")
            if isDirectoryOnly { rule = String(rule.dropLast()) }

            gitignoreRules.append((pattern: rule, isNegation: isNegation, isDirectoryOnly: isDirectoryOnly))
        }
        Self.logger.debug("loadGitignoreRules: loaded \(self.gitignoreRules.count) rules")
    }

    /// Check if a relative path is gitignored (last matching rule wins, like git)
    func isGitignored(_ relativePath: String, isDirectory: Bool) -> Bool {
        guard respectGitignore, !gitignoreRules.isEmpty, !relativePath.isEmpty else { return false }

        var ignored = false
        for rule in gitignoreRules {
            // Directory-only rules don't apply to files
            if rule.isDirectoryOnly && !isDirectory { continue }

            let matches: Bool
            if rule.pattern.contains("*") || rule.pattern.contains("?") {
                matches = matchGlob(pattern: rule.pattern.lowercased(), path: relativePath.lowercased())
            } else if rule.pattern.contains("/") {
                // Path-based rule: match as prefix
                matches = relativePath == rule.pattern || relativePath.hasPrefix(rule.pattern + "/")
            } else {
                // Name-based rule: match any path component
                let name = (relativePath as NSString).lastPathComponent
                matches = name == rule.pattern || relativePath.hasSuffix("/\(rule.pattern)")
            }

            if matches {
                ignored = !rule.isNegation
            }
        }
        return ignored
    }

    /// Check if a file should be excluded by file patterns
    func isFileExcluded(_ relativePath: String) -> Bool {
        guard !excludedFilePatterns.isEmpty else { return false }
        for pattern in excludedFilePatterns {
            let trimmed = pattern.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            if matchGlob(pattern: trimmed.lowercased(), path: relativePath.lowercased()) {
                return true
            }
        }
        return false
    }

    // MARK: - Private: Pattern Matching

    /// Simple fuzzy subsequence match
    func fuzzyMatch(query: String, target: String) -> Bool {
        var queryIdx = query.startIndex
        var targetIdx = target.startIndex

        while queryIdx < query.endIndex && targetIdx < target.endIndex {
            if query[queryIdx] == target[targetIdx] {
                queryIdx = query.index(after: queryIdx)
            }
            targetIdx = target.index(after: targetIdx)
        }

        return queryIdx == query.endIndex
    }

    /// Simplified glob matching (supports * and **)
    func matchGlob(pattern: String, path: String) -> Bool {
        // Simple cases
        if pattern == "*" { return true }
        if pattern == path { return true }

        // Convert glob to a simple check
        if pattern.hasPrefix("**/*.") || pattern.hasPrefix("*.") {
            let ext = String(pattern.split(separator: ".").last ?? "")
            return path.hasSuffix(".\(ext)")
        }

        if pattern.hasPrefix("**/") {
            let suffix = String(pattern.dropFirst(3))
            return path.hasSuffix(suffix) || path.contains("/\(suffix)")
        }

        if pattern.hasSuffix("/**") {
            let prefix = String(pattern.dropLast(3))
            return path.hasPrefix(prefix)
        }

        if pattern.contains("*") {
            let parts = pattern.split(separator: "*", omittingEmptySubsequences: false).map(
                String.init)
            var searchFrom = path.startIndex
            for part in parts {
                if part.isEmpty { continue }
                guard let range = path.range(of: part, range: searchFrom..<path.endIndex) else {
                    return false
                }
                searchFrom = range.upperBound
            }
            return true
        }

        return path.contains(pattern)
    }
}
