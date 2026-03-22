import Foundation

extension DebugStore {
    /// Extracts structured findings from a debug chat assistant response.
    /// Parses common patterns like file references, error mentions, and fix suggestions.
    func syncStructuredFindingsFromChatResponse(content: String) {
        let lines = content.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            // Skip empty lines and short lines
            guard trimmed.count > 10 else { continue }

            // Pattern: file:line references (e.g., "src/main.swift:42")
            if let fileRef = extractFileReference(from: trimmed) {
                let alreadyExists = debugFindings.contains {
                    $0.filePath == fileRef.path && $0.lineNumber == fileRef.line
                }
                if !alreadyExists {
                    let finding = DebugFinding(
                        title: String(trimmed.prefix(80)),
                        filePath: fileRef.path,
                        lineNumber: fileRef.line,
                        severity: .medium,
                        status: .open
                    )
                    debugFindings.append(finding)
                }
            }
        }
    }

    /// Extracts a file:line reference from a text line.
    private func extractFileReference(from text: String) -> (path: String, line: Int)? {
        // Match patterns like "path/to/file.swift:42" or "path/to/file.swift line 42"
        let patterns = [
            "([\\w/._-]+\\.\\w+):(\\d+)",
            "([\\w/._-]+\\.\\w+)\\s+line\\s+(\\d+)"
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            if let match = regex.firstMatch(in: text, options: [], range: range) {
                guard match.numberOfRanges >= 3,
                      let pathRange = Range(match.range(at: 1), in: text),
                      let lineRange = Range(match.range(at: 2), in: text),
                      let lineNumber = Int(text[lineRange])
                else { continue }

                let path = String(text[pathRange])
                // Only accept paths that look like source files
                let sourceExtensions = ["swift", "rs", "ts", "js", "py", "go", "c", "cpp", "h", "m"]
                let ext = (path as NSString).pathExtension.lowercased()
                if sourceExtensions.contains(ext) {
                    return (path, lineNumber)
                }
            }
        }

        return nil
    }
}
