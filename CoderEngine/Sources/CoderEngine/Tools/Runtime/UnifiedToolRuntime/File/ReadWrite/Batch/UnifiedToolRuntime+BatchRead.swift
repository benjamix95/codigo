import Foundation

extension UnifiedToolRuntime {
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
}
