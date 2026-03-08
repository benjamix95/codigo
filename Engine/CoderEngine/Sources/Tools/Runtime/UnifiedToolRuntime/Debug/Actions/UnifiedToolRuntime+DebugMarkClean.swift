import Foundation

extension UnifiedToolRuntime {
    func executeDebugMark(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let rawPath = call.args["path"] ?? ""
        let lineStr = call.args["line"] ?? ""
        let comment = call.args["comment"] ?? "DEBUG"
        let code = call.args["code"] ?? ""
        let markerType = (call.args["type"] ?? "marker").lowercased()
        let expression = call.args["expression"] ?? ""
        let hypothesisId = call.args["hypothesis_id"] ?? ""

        guard !rawPath.isEmpty else {
            return ToolResult(ok: false, payload: ["detail": "path is required"], durationMs: 0)
        }
        guard let lineNum = Int(lineStr), lineNum > 0 else {
            return ToolResult(ok: false, payload: ["detail": "valid line number is required"], durationMs: 0)
        }

        let path: String
        do {
            path = try resolveRequiredPath(rawPath, context: context)
        } catch let err as ToolRuntimeError {
            return ToolResult(ok: false, payload: ["detail": err.localizedDescription], durationMs: 0)
        } catch {
            return ToolResult(ok: false, payload: ["detail": error.localizedDescription], durationMs: 0)
        }
        let ms = Int(Date().timeIntervalSince(startDate) * 1000)
        let hypTag = hypothesisId.isEmpty ? "" : " [H:\(hypothesisId.prefix(8))]"

        do {
            let content = try String(contentsOfFile: path, encoding: .utf8)
            var lines = content.components(separatedBy: "\n")
            let insertIdx = min(lineNum, lines.count)

            let markerLine: String
            if !code.isEmpty {
                markerLine = code + " // \u{1F41B} DEBUG[\(markerType)]: \(comment)\(hypTag)"
            } else {
                switch markerType {
                case "log":
                    let expr = expression.isEmpty ? "\"checkpoint\"" : expression
                    markerLine = "print(\"\\u{1F41B} DEBUG[\\(#file):\\(#line)] \(comment): \\(\(expr))\") // \u{1F41B} DEBUG[log]: \(comment)\(hypTag)"
                case "assert":
                    let expr = expression.isEmpty ? "true" : expression
                    markerLine = "assert(\(expr), \"\\u{1F41B} DEBUG ASSERT: \(comment)\") // \u{1F41B} DEBUG[assert]: \(comment)\(hypTag)"
                case "timing":
                    markerLine = "let _debugTimerStart_\(lineNum) = CFAbsoluteTimeGetCurrent(); defer { print(\"\\u{1F41B} DEBUG TIMING [\(comment)]: \\(CFAbsoluteTimeGetCurrent() - _debugTimerStart_\(lineNum))s\") } // \u{1F41B} DEBUG[timing]: \(comment)\(hypTag)"
                case "variable":
                    let expr = expression.isEmpty ? "self" : expression
                    markerLine = "print(\"\\u{1F41B} DEBUG VAR [\(comment)] \(expr) = \\(\(expr))\") // \u{1F41B} DEBUG[variable]: \(comment)\(hypTag)"
                default:
                    markerLine = "// \u{1F41B} DEBUG[marker]: \(comment)\(hypTag)"
                }
            }

            lines.insert(markerLine, at: insertIdx)
            try lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: String.Encoding.utf8)

            await debugLogServer.log(
                severity: "info",
                source: "debug_mark",
                message: "[\(markerType)] Marker inserted at \((path as NSString).lastPathComponent):\(lineNum)",
                detail: markerLine,
                category: "debug"
            )

            return ToolResult(ok: true, payload: [
                "title": "debug_mark",
                "detail": "[\(markerType)] marker at \((path as NSString).lastPathComponent):\(lineNum)",
                "output": "Inserted [\(markerType)]: \(markerLine)",
                "marker_info": "\(path)|\(lineNum)|\(comment)|\(markerType)",
                "path": path,
                "line": "\(lineNum)",
                "comment": comment,
                "type": markerType,
                "hypothesis_id": hypothesisId
            ], durationMs: ms)
        } catch {
            return ToolResult(ok: false, payload: [
                "title": "debug_mark",
                "detail": "Failed to insert marker: \(error.localizedDescription)"
            ], durationMs: ms)
        }
    }

    // MARK: - debug_clean: Remove debug markers with type filtering, dry-run, and hypothesis scoping

    func executeDebugClean(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let rawPath = call.args["path"] ?? ""
        let cleanType = (call.args["type"] ?? "all").lowercased()
        let isDryRun = call.args["dry_run"]?.lowercased() == "true"
        let hypothesisId = call.args["hypothesis_id"] ?? ""
        let normalizedHypothesisPrefix = String(
            hypothesisId
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .prefix(8)
        )
        let workspace = context.workspaceContext.workspacePath.path
        let debugTag = "\u{1F41B} DEBUG"
        var cleanedCount = 0
        var previewLines: [String] = []
        var errors: [String] = []

        let filesToClean: [String]
        if !rawPath.isEmpty {
            do {
                filesToClean = [try resolveRequiredPath(rawPath, context: context)]
            } catch let err as ToolRuntimeError {
                return ToolResult(ok: false, payload: ["detail": err.localizedDescription], durationMs: 0)
            } catch {
                return ToolResult(ok: false, payload: ["detail": error.localizedDescription], durationMs: 0)
            }
        } else {
            if let rgPath = await resolveRipgrepPath(cwd: workspace) {
                let (output, _, _) = await shellExec(
                    args: [rgPath, "-l", "--no-heading", debugTag, workspace],
                    cwd: workspace,
                    timeout: 15_000
                )
                filesToClean = output.components(separatedBy: "\n").filter { !$0.isEmpty }
            } else {
                filesToClean = discoverFilesContaining(debugTag, under: workspace)
            }
        }

        let typePatterns: [String]
        switch cleanType {
        case "markers": typePatterns = ["DEBUG[marker]"]
        case "logs": typePatterns = ["DEBUG[log]", "DEBUG[instrument-log]"]
        case "asserts": typePatterns = ["DEBUG[assert]", "DEBUG[instrument-assert]", "DEBUG[instrument-conditional]"]
        case "timing": typePatterns = ["DEBUG[timing]", "DEBUG[instrument-timing]"]
        case "variables": typePatterns = ["DEBUG[variable]", "DEBUG[instrument-variable]"]
        default: typePatterns = [debugTag]
        }

        for filePath in filesToClean {
            do {
                let content = try String(contentsOfFile: filePath, encoding: .utf8)
                let lines = content.components(separatedBy: "\n")
                let fileName = (filePath as NSString).lastPathComponent

                let filtered = lines.enumerated().compactMap { (idx, line) -> String? in
                    let normalizedLine = line.lowercased()
                    let shouldRemove = typePatterns.contains(where: { normalizedLine.contains($0.lowercased()) })
                    let matchesHypothesis = normalizedHypothesisPrefix.isEmpty
                        || normalizedLine.contains("[h:\(normalizedHypothesisPrefix)]")

                    if shouldRemove && matchesHypothesis {
                        cleanedCount += 1
                        if isDryRun {
                            previewLines.append("  \(fileName):\(idx + 1) | \(line.trimmingCharacters(in: .whitespaces))")
                        }
                        return nil
                    }
                    return line
                }

                if !isDryRun && filtered.count < lines.count {
                    try filtered.joined(separator: "\n").write(toFile: filePath, atomically: true, encoding: String.Encoding.utf8)
                }
            } catch {
                errors.append("\((filePath as NSString).lastPathComponent): \(error.localizedDescription)")
            }
        }

        let ms = Int(Date().timeIntervalSince(startDate) * 1000)
        let modeLabel = isDryRun ? "DRY RUN" : "CLEANED"
        let typeLabel = cleanType == "all" ? "all types" : cleanType
        let detail: String
        let isSuccess: Bool

        if !errors.isEmpty {
            detail = "[\(modeLabel)] \(cleanedCount) markers (\(typeLabel)) in \(filesToClean.count) files; errors: \(errors.prefix(3).joined(separator: "; "))"
            isSuccess = false
        } else if cleanedCount == 0 {
            detail = "No \(typeLabel) debug markers found"
            isSuccess = true
        } else {
            detail = "[\(modeLabel)] \(cleanedCount) \(typeLabel) markers in \(filesToClean.count) files"
            isSuccess = true
        }

        var output = detail
        if isDryRun && !previewLines.isEmpty {
            output += "\n\nWould remove:\n" + previewLines.prefix(30).joined(separator: "\n")
            if previewLines.count > 30 { output += "\n  ... +\(previewLines.count - 30) more" }
        }

        await debugLogServer.log(severity: "info", source: "debug_clean", message: detail, category: "debug")

        return ToolResult(ok: isSuccess, payload: [
            "title": "debug_clean",
            "detail": detail,
            "output": output,
            "cleaned_markers": "\(cleanedCount)",
            "cleaned_files": "\(filesToClean.count)",
            "type": cleanType,
            "dry_run": isDryRun ? "true" : "false",
            "status": isDryRun ? "preview" : (isSuccess ? "completed" : "failed")
        ], durationMs: ms)
    }

    // MARK: - debug_trace_analyze: Parse and analyze errors, stack traces, crash logs

}
