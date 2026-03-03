import Foundation

extension UnifiedToolRuntime {
    func executeWrite(call: ToolCall, context: ToolExecutionContext, startDate: Date) throws -> ToolResult {
        guard let pathArg = call.args["path"] else {
            throw ToolRuntimeError.validation("Missing path")
        }
        let path = try resolveRequiredPath(pathArg, context: context)
        let content = call.args["content"] ?? ""
        let oldContent = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        try content.write(toFile: path, atomically: true, encoding: .utf8)
        let added = max(0, content.split(separator: "\n").count - oldContent.split(separator: "\n").count)
        let removed = max(0, oldContent.split(separator: "\n").count - content.split(separator: "\n").count)
        let diffPreview = buildDiffPreview(old: oldContent, new: content)
        return success([
            "title": "Edit \(path)",
            "path": path,
            "file": path,
            "linesAdded": "\(added)",
            "linesRemoved": "\(removed)",
            "diffPreview": diffPreview
        ], startDate: startDate)
    }

    func executeStrReplace(call: ToolCall, context: ToolExecutionContext, startDate: Date) throws -> ToolResult {
        guard let pathArg = call.args["path"] else {
            throw ToolRuntimeError.validation("path is required")
        }
        let path = try resolveRequiredPath(pathArg, context: context)
        guard FileManager.default.fileExists(atPath: path) else {
            throw ToolRuntimeError.validation("File not found: \(path). Use create_file for new files.")
        }
        let oldString = call.args["old_string"] ?? ""
        let newString = call.args["new_string"] ?? ""

        guard !oldString.isEmpty else {
            throw ToolRuntimeError.validation("old_string is required and cannot be empty")
        }

        let content = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""

        // Count occurrences
        let occurrences = content.components(separatedBy: oldString).count - 1

        if occurrences == 0 {
            // Try to find the closest match to help the user
            let oldLines = oldString.components(separatedBy: "\n")
            let firstLine = oldLines.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            var hint = ""
            if !firstLine.isEmpty {
                let contentLines = content.components(separatedBy: "\n")
                for (idx, line) in contentLines.enumerated() {
                    if line.contains(firstLine) {
                        let start = max(0, idx - 1)
                        let end = min(contentLines.count, idx + 4)
                        let snippet = contentLines[start..<end].enumerated().map { i, l in
                            "\(start + i + 1)│\(l)"
                        }.joined(separator: "\n")
                        hint = "\n\nClosest match found near line \(idx + 1):\n\(snippet)\n\nMake sure old_string matches EXACTLY including whitespace and indentation."
                        break
                    }
                }
            }
            throw ToolRuntimeError.validation("old_string not found in \(path).\(hint)")
        }

        if occurrences > 1 {
            // Find all locations to help user add context
            let contentLines = content.components(separatedBy: "\n")
            let firstOldLine = oldString.components(separatedBy: "\n").first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? oldString
            var locations: [Int] = []
            for (idx, line) in contentLines.enumerated() {
                if line.contains(firstOldLine) {
                    locations.append(idx + 1)
                }
            }
            let locationStr = locations.prefix(5).map { "line \($0)" }.joined(separator: ", ")
            throw ToolRuntimeError.validation("old_string is not unique — found \(occurrences) occurrences at \(locationStr). Add more surrounding context to make it unique.")
        }

        // Perform the replacement (exactly 1 match)
        let newContent = content.replacingOccurrences(of: oldString, with: newString)
        try newContent.write(toFile: path, atomically: true, encoding: .utf8)

        // Build a nice diff preview
        let oldLines = oldString.components(separatedBy: "\n")
        let newLines = newString.components(separatedBy: "\n")
        var diffPreview = ""
        for line in oldLines.prefix(15) {
            diffPreview += "- \(line)\n"
        }
        for line in newLines.prefix(15) {
            diffPreview += "+ \(line)\n"
        }

        // Find the line number where the change was made
        let lineNumber: Int
        if let range = content.range(of: oldString) {
            let beforeReplacement = content[content.startIndex..<range.lowerBound]
            lineNumber = beforeReplacement.filter { $0 == "\n" }.count + 1
        } else {
            lineNumber = 1
        }

        return success([
            "title": "str_replace \((path as NSString).lastPathComponent):\(lineNumber)",
            "path": path,
            "file": path,
            "detail": "Replaced at line \(lineNumber) (\(oldLines.count) lines → \(newLines.count) lines)",
            "diffPreview": diffPreview.trimmingCharacters(in: .whitespacesAndNewlines)
        ], startDate: startDate)
    }

    func executeCreateFile(call: ToolCall, context: ToolExecutionContext, startDate: Date) throws -> ToolResult {
        guard let pathArg = call.args["path"] else {
            throw ToolRuntimeError.validation("path is required")
        }
        let path = try resolveRequiredPath(pathArg, context: context)
        let content = call.args["content"] ?? ""

        if FileManager.default.fileExists(atPath: path) {
            throw ToolRuntimeError.validation("File already exists: \(path). Use str_replace to edit or write to overwrite.")
        }

        // Create intermediate directories if needed
        let dirPath = (path as NSString).deletingLastPathComponent
        if !FileManager.default.fileExists(atPath: dirPath) {
            try FileManager.default.createDirectory(atPath: dirPath, withIntermediateDirectories: true)
        }

        try content.write(toFile: path, atomically: true, encoding: .utf8)
        let lineCount = content.components(separatedBy: "\n").count
        return success([
            "title": "Created \((path as NSString).lastPathComponent)",
            "path": path,
            "file": path,
            "detail": "Created \(lineCount) lines",
            "linesAdded": "\(lineCount)"
        ], startDate: startDate)
    }
}
