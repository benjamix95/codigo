import Foundation

extension UnifiedToolRuntime {
    func executeRead(call: ToolCall, context: ToolExecutionContext, startDate: Date) throws -> ToolResult {
        let path = try resolveRequiredPath(call.args["path"], context: context)
        guard let handle = FileHandle(forReadingAtPath: path) else {
            throw ToolRuntimeError.validation("File not found: \(path)")
        }
        defer { try? handle.close() }

        let data = try handle.read(upToCount: context.policy.maxReadBytesPerFile) ?? Data()
        let rawContent = String(data: data, encoding: .utf8) ?? ""
        let allLines = rawContent.components(separatedBy: "\n")

        let offsetLine = max(1, Int(call.args["offset"] ?? "1") ?? 1)
        let startIndex = max(0, offsetLine - 1)
        let requestedLimit = Int(call.args["limit"] ?? "") ?? 0
        let endIndex: Int = {
            guard requestedLimit > 0 else { return allLines.count }
            return min(allLines.count, startIndex + requestedLimit)
        }()

        let selectedLines: ArraySlice<String>
        if startIndex >= allLines.count {
            selectedLines = []
        } else {
            selectedLines = allLines[startIndex..<endIndex]
        }

        let digitCount = max(1, String(allLines.count).count)
        let numberedLines = selectedLines.enumerated().map { idx, line in
            let num = String(startIndex + idx + 1)
            let padding = String(repeating: " ", count: max(0, digitCount - num.count))
            return "\(padding)\(num)│\(line)"
        }
        let content = numberedLines.joined(separator: "\n")

        return success([
            "title": "Read \(path)",
            "path": path,
            "output": content,
            "detail": "\(selectedLines.count) lines"
        ], startDate: startDate)
    }

    func executeReadRange(call: ToolCall, context: ToolExecutionContext, startDate: Date) throws -> ToolResult {
        let path = try resolveRequiredPath(call.args["path"], context: context)
        let startLine = max(1, Int(call.args["start"] ?? call.args["start_line"] ?? "1") ?? 1)
        let endLineRaw = Int(call.args["end"] ?? call.args["end_line"] ?? "0") ?? 0
        let content = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        let lines = content.components(separatedBy: .newlines)
        let endLine = endLineRaw > 0 ? min(lines.count, endLineRaw) : min(lines.count, startLine + 200)
        if startLine > endLine || startLine > lines.count {
            throw ToolRuntimeError.validation("Invalid line range")
        }
        let segment = lines[(startLine - 1)..<endLine].enumerated().map { idx, line in
            "\(startLine + idx): \(line)"
        }.joined(separator: "\n")
        return success([
            "title": "Read range \(path):\(startLine)-\(endLine)",
            "path": path,
            "output": truncate(segment, maxBytes: context.policy.maxReadBytesPerFile)
        ], startDate: startDate)
    }

    func executeListDir(call: ToolCall, context: ToolExecutionContext, startDate: Date) throws -> ToolResult {
        let path = try resolveRequiredPath(call.args["path"] ?? ".", context: context)
        let maxEntries = max(1, min(1000, Int(call.args["maxEntries"] ?? "200") ?? 200))
        let url = URL(fileURLWithPath: path)
        let entries = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        let excludedSet = Set(context.workspaceContext.excludedPaths)
        let filtered = entries.filter { entry in
            let name = entry.lastPathComponent
            if excludedSet.contains(name) { return false }
            if excludedSet.contains(entry.path) { return false }
            for ws in context.workspaceContext.workspacePaths {
                let rel = entry.path.replacingOccurrences(of: ws.path + "/", with: "")
                if excludedSet.contains(rel) { return false }
            }
            return true
        }
        let sorted = filtered
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .prefix(maxEntries)
            .map { entry -> String in
                let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                return isDir ? "\(entry.lastPathComponent)/" : entry.lastPathComponent
            }
        return success([
            "title": "List dir \(path)",
            "path": path,
            "detail": "\(sorted.count) entries",
            "output": sorted.joined(separator: "\n")
        ], startDate: startDate)
    }

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

    func executeReadJSON(call: ToolCall, context: ToolExecutionContext, startDate: Date) throws -> ToolResult {
        let path = try resolveRequiredPath(call.args["path"], context: context)
        let content = try String(contentsOfFile: path, encoding: .utf8)
        guard let data = content.data(using: .utf8) else {
            throw ToolRuntimeError.validation("JSON cannot be read")
        }
        let obj: Any
        do {
            obj = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ToolRuntimeError.validation("Invalid JSON")
        }
        let pretty = prettyJSON(obj)
        return success([
            "title": "Read JSON \(path)",
            "path": path,
            "output": truncate(pretty, maxBytes: context.policy.maxReadBytesPerFile)
        ], startDate: startDate)
    }

    func executeWriteJSON(call: ToolCall, context: ToolExecutionContext, startDate: Date) throws -> ToolResult {
        let path = try resolveRequiredPath(call.args["path"], context: context)
        guard let patchRaw = call.args["patch"], !patchRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolRuntimeError.validation("patch JSON is required")
        }
        let patchObj = try parseJSONObject(from: patchRaw)
        let existingObj: Any
        if FileManager.default.fileExists(atPath: path) {
            let existingData = try Data(contentsOf: URL(fileURLWithPath: path))
            existingObj = try JSONSerialization.jsonObject(with: existingData)
        } else {
            existingObj = [String: Any]()
        }
        guard var merged = existingObj as? [String: Any] else {
            throw ToolRuntimeError.validation("write_json supports only JSON object root")
        }
        if let patchDict = patchObj as? [String: Any] {
            for (k, v) in patchDict { merged[k] = v }
        } else {
            throw ToolRuntimeError.validation("patch must be a JSON object")
        }
        let output = try JSONSerialization.data(withJSONObject: merged, options: [.prettyPrinted, .sortedKeys])
        try output.write(to: URL(fileURLWithPath: path), options: .atomic)
        return success([
            "title": "Write JSON \(path)",
            "path": path,
            "detail": "Patch applied",
            "output": String(data: output, encoding: .utf8) ?? ""
        ], startDate: startDate)
    }

    func executeParallelApply(call: ToolCall, context: ToolExecutionContext, startDate: Date) async throws -> ToolResult {
        guard let editsRaw = call.args["edits"], !editsRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolRuntimeError.validation("edits (JSON array) is required for parallel_apply")
        }
        guard let editsData = editsRaw.data(using: .utf8),
              let editsArray = try? JSONSerialization.jsonObject(with: editsData) as? [[String: String]] else {
            throw ToolRuntimeError.validation("edits must be a JSON array of objects with path, old_string, new_string")
        }
        guard !editsArray.isEmpty else {
            throw ToolRuntimeError.validation("edits array is empty")
        }

        var results: [(path: String, ok: Bool, detail: String)] = []
        for edit in editsArray {
            let editCall = ToolCall(
                id: UUID().uuidString,
                name: "str_replace",
                args: edit,
                sourceProvider: call.sourceProvider,
                swarmId: call.swarmId,
                scope: call.scope
            )
            do {
                let result = try executeStrReplace(call: editCall, context: context, startDate: Date())
                results.append((
                    path: edit["path"] ?? "?",
                    ok: result.ok,
                    detail: result.payload["detail"] ?? (result.ok ? "ok" : "failed")
                ))
            } catch {
                results.append((path: edit["path"] ?? "?", ok: false, detail: error.localizedDescription))
            }
        }

        let summary = results.map { "\($0.ok ? "OK" : "FAIL") \($0.path): \($0.detail)" }.joined(separator: "\n")
        let allOk = results.allSatisfy(\.ok)
        let successCount = results.filter(\.ok).count
        return ToolResult(
            ok: allOk,
            payload: [
                "title": "parallel_apply (\(results.count) edits)",
                "output": summary,
                "detail": "\(successCount)/\(results.count) edits succeeded"
            ],
            durationMs: max(1, Int(Date().timeIntervalSince(startDate) * 1000))
        )
    }

    // MARK: - New Tool: regex_replace

    func executeRegexReplace(call: ToolCall, context: ToolExecutionContext, startDate: Date) throws -> ToolResult {
        guard let pathArg = call.args["path"] else {
            throw ToolRuntimeError.validation("path is required")
        }
        let path = try resolveRequiredPath(pathArg, context: context)
        guard FileManager.default.fileExists(atPath: path) else {
            throw ToolRuntimeError.validation("File not found: \(path)")
        }

        let pattern = call.args["pattern"] ?? ""
        let replacement = call.args["replacement"] ?? ""
        guard !pattern.isEmpty else {
            throw ToolRuntimeError.validation("pattern (regex) is required")
        }

        let flags = call.args["flags"] ?? ""
        var options: NSRegularExpression.Options = []
        if flags.contains("i") { options.insert(.caseInsensitive) }
        if flags.contains("m") { options.insert(.anchorsMatchLines) }
        if flags.contains("s") { options.insert(.dotMatchesLineSeparators) }

        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            throw ToolRuntimeError.validation("Invalid regex pattern: \(error.localizedDescription)")
        }

        let content = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        let range = NSRange(content.startIndex..., in: content)
        let matchCount = regex.numberOfMatches(in: content, range: range)

        guard matchCount > 0 else {
            return success([
                "title": "regex_replace (0 matches)",
                "path": path,
                "detail": "Pattern '\(pattern)' not found in \(path)"
            ], startDate: startDate)
        }

        let newContent = regex.stringByReplacingMatches(in: content, range: range, withTemplate: replacement)
        try newContent.write(toFile: path, atomically: true, encoding: .utf8)

        return success([
            "title": "regex_replace \((path as NSString).lastPathComponent)",
            "path": path,
            "file": path,
            "detail": "Replaced \(matchCount) match(es) of /\(pattern)/\(flags)"
        ], startDate: startDate)
    }

    // MARK: - New Tool: attempt_completion

    func executeApplyDiff(call: ToolCall, context: ToolExecutionContext, startDate: Date) throws -> ToolResult {
        let path = try resolveRequiredPath(call.args["path"], context: context)
        let diff = (call.args["diff"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !diff.isEmpty else {
            throw ToolRuntimeError.validation("diff is required — provide a unified diff string")
        }
        guard FileManager.default.fileExists(atPath: path) else {
            throw ToolRuntimeError.validation("File not found: \(path)")
        }

        let content = try String(contentsOfFile: path, encoding: .utf8)
        var lines = content.components(separatedBy: "\n")
        var applied = 0
        var offset = 0

        let diffLines = diff.components(separatedBy: "\n")
        var i = 0
        while i < diffLines.count {
            let line = diffLines[i]
            if line.hasPrefix("@@") {
                let header = line
                let regex = try? NSRegularExpression(pattern: #"@@ -(\d+)(?:,\d+)? \+\d+(?:,\d+)? @@"#)
                let match = regex?.firstMatch(in: header, range: NSRange(header.startIndex..., in: header))
                guard let m = match,
                      let startRange = Range(m.range(at: 1), in: header),
                      let startLine = Int(header[startRange]) else {
                    i += 1
                    continue
                }

                var hunkRemovals: [Int] = []
                var hunkAdditions: [String] = []
                var pos = startLine - 1 + offset
                i += 1

                while i < diffLines.count && !diffLines[i].hasPrefix("@@") && !diffLines[i].hasPrefix("diff ") {
                    let dl = diffLines[i]
                    if dl.hasPrefix("-") {
                        if pos < lines.count {
                            hunkRemovals.append(pos)
                        }
                        pos += 1
                    } else if dl.hasPrefix("+") {
                        hunkAdditions.append(String(dl.dropFirst()))
                    } else if dl.hasPrefix(" ") || dl.isEmpty {
                        pos += 1
                    }
                    i += 1
                }

                let insertionBase = hunkRemovals.first ?? (startLine - 1 + offset)
                for idx in hunkRemovals.sorted().reversed() where idx < lines.count {
                    lines.remove(at: idx)
                }
                let insertAt = min(lines.count, insertionBase)
                for (j, text) in hunkAdditions.enumerated() {
                    lines.insert(text, at: min(lines.count, insertAt + j))
                }

                offset += hunkAdditions.count - hunkRemovals.count
                applied += 1
            } else {
                i += 1
            }
        }

        guard applied > 0 else {
            throw ToolRuntimeError.validation("No valid diff hunks found. Use unified diff format with @@ headers.")
        }

        let newContent = lines.joined(separator: "\n")
        try newContent.write(toFile: path, atomically: true, encoding: .utf8)

        return success([
            "title": "apply_diff \((path as NSString).lastPathComponent)",
            "path": path,
            "file": path,
            "detail": "Applied \(applied) diff hunks",
            "output": "Applied \(applied) hunks to \((path as NSString).lastPathComponent)"
        ], startDate: startDate)
    }

    // MARK: - batch_read

    func executeBatchRead(call: ToolCall, context: ToolExecutionContext, startDate: Date) throws -> ToolResult {
        let pathsRaw = (call.args["paths"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pathsRaw.isEmpty else {
            throw ToolRuntimeError.validation("paths is required — JSON array of file paths or comma-separated paths")
        }

        var paths: [String] = []
        if pathsRaw.hasPrefix("["),
           let data = pathsRaw.data(using: .utf8),
           let arr = try? JSONSerialization.jsonObject(with: data) as? [String] {
            paths = arr
        } else {
            paths = pathsRaw.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }

        paths = paths.filter { !$0.isEmpty }
        guard !paths.isEmpty else {
            throw ToolRuntimeError.validation("No valid file paths provided")
        }
        guard paths.count <= 20 else {
            throw ToolRuntimeError.validation("Too many files — max 20 per batch_read call")
        }

        let maxPerFile = context.policy.maxReadBytesPerFile
        var output = ""
        var readCount = 0

        for rawPath in paths {
            guard let resolvedPath = resolvePath(rawPath,
                                                 workspacePaths: context.workspaceContext.workspacePaths.map(\.path),
                                                 preferredRoot: context.workspaceContext.activeRootPath,
                                                 sandboxMode: context.policy.sandboxMode) else {
                output += "### \(rawPath)\n[error: path not allowed]\n\n"
                continue
            }

            guard let handle = FileHandle(forReadingAtPath: resolvedPath) else {
                output += "### \(rawPath)\n[error: file not found]\n\n"
                continue
            }
            defer { try? handle.close() }

            let data = (try? handle.read(upToCount: maxPerFile)) ?? Data()
            let fileContent = String(data: data, encoding: .utf8) ?? "[binary file]"
            let fileLines = fileContent.components(separatedBy: "\n")
            let lineCount = fileLines.count

            let digitWidth = max(1, String(lineCount).count)
            let numbered = fileLines.enumerated().map { idx, line in
                let num = String(idx + 1)
                let pad = String(repeating: " ", count: max(0, digitWidth - num.count))
                return "\(pad)\(num)|\(line)"
            }.joined(separator: "\n")

            output += "### \(rawPath) (\(lineCount) lines)\n\(numbered)\n\n"
            readCount += 1
        }

        return success([
            "title": "batch_read (\(readCount)/\(paths.count) files)",
            "detail": "Read \(readCount) files",
            "output": truncate(output, maxBytes: context.policy.maxBashOutputBytes)
        ], startDate: startDate)
    }

    // MARK: - diff_files
}
