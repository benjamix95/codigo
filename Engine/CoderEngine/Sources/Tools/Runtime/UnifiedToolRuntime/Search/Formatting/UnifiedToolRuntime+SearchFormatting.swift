import Foundation

extension UnifiedToolRuntime {
    func containsRegexChars(_ s: String) -> Bool {
        let regexSpecial = CharacterSet(charactersIn: ".*+?[](){}^$|\\")
        return s.unicodeScalars.contains { regexSpecial.contains($0) }
    }

    func rankGrepResults(_ output: String, query: String) -> String {
        let lines = output.components(separatedBy: "\n")
        guard lines.count > 5 else { return output }

        // Group results by file
        struct FileResults {
            var path: String
            var lines: [String]
            var score: Int
        }

        var fileGroups: [String: [String]] = [:]
        var currentFile: String?

        for line in lines {
            if line.contains(":") && !line.hasPrefix("-") && !line.hasPrefix(" ") {
                let parts = line.split(separator: ":", maxSplits: 2)
                if parts.count >= 2, let _ = Int(parts[1]) {
                    currentFile = String(parts[0])
                }
            }
            if let file = currentFile {
                fileGroups[file, default: []].append(line)
            }
        }

        if fileGroups.isEmpty { return output }

        // Score files: source files > config > docs, shorter paths > deeper
        let sourceExts: Set<String> = ["swift", "ts", "tsx", "js", "jsx", "py", "go", "rs", "java", "kt", "rb"]
        let scored = fileGroups.map { (path, resultLines) -> FileResults in
            var score = 0
            let ext = (path as NSString).pathExtension.lowercased()
            if sourceExts.contains(ext) { score += 100 }
            let depth = path.components(separatedBy: "/").count
            score += max(0, 20 - depth * 2)
            // Exact match bonus
            if resultLines.contains(where: { $0.lowercased().contains(query.lowercased()) }) {
                score += 50
            }
            return FileResults(path: path, lines: resultLines, score: score)
        }.sorted { $0.score > $1.score }

        return scored.flatMap { $0.lines }.joined(separator: "\n")
    }

    func extractSearchMatchLines(_ output: String, limit: Int = .max) -> [String] {
        var matches: [String] = []
        var seen = Set<String>()

        for rawLine in output.components(separatedBy: "\n") {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let parts = rawLine.split(separator: ":", maxSplits: 2).map(String.init)
            guard parts.count >= 3, let lineNumber = Int(parts[1]) else { continue }
            let preview = parts[2].trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = "\(parts[0]):\(lineNumber):\(preview)"
            guard seen.insert(normalized).inserted else { continue }
            matches.append(normalized)
            if matches.count >= limit { break }
        }

        return matches
    }
}
