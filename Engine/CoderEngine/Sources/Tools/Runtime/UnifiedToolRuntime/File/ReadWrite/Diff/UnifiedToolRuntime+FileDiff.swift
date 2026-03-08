import Foundation

extension UnifiedToolRuntime {
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
}
