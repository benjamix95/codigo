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
}
