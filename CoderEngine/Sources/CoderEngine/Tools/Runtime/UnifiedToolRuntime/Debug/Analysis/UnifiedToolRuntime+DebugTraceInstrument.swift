import Foundation

extension UnifiedToolRuntime {
    func executeDebugTraceAnalyze(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let errorText = call.args["error_text"] ?? ""
        let errorTypeHint = (call.args["error_type"] ?? "").lowercased()
        let extraContext = call.args["context"] ?? ""
        let workspace = context.workspaceContext.workspacePath.path

        guard !errorText.isEmpty else {
            return ToolResult(ok: false, payload: ["detail": "error_text is required"], durationMs: 0)
        }

        var analysis: [String] = []
        var extractedFiles: [(file: String, line: Int, col: Int?)] = []
        var suggestedCauses: [String] = []

        // Auto-detect error type
        let detectedType: String
        if !errorTypeHint.isEmpty {
            detectedType = errorTypeHint
        } else if errorText.contains("error:") && (errorText.contains(".swift:") || errorText.contains(".m:")) {
            detectedType = "compile"
        } else if errorText.contains("Fatal error") || errorText.contains("Thread ") || errorText.contains("EXC_") {
            detectedType = "crash"
        } else if errorText.contains("XCTAssert") || errorText.contains("failed -") || errorText.contains("FAIL") {
            detectedType = "test_failure"
        } else if errorText.contains("Assertion failed") || errorText.contains("precondition") {
            detectedType = "assertion"
        } else {
            detectedType = "runtime"
        }
        analysis.append("## Error Type: \(detectedType)")

        let lines = errorText.components(separatedBy: "\n")

        // Parse Swift compiler errors: file.swift:line:col: error: message
        let compilerPattern = try? NSRegularExpression(pattern: #"([^\s:]+\.\w+):(\d+):(\d+):\s*(error|warning|note):\s*(.+)"#)
        for line in lines {
            let range = NSRange(line.startIndex..., in: line)
            if let match = compilerPattern?.firstMatch(in: line, range: range) {
                let file = String(line[Range(match.range(at: 1), in: line)!])
                let lineNum = Int(line[Range(match.range(at: 2), in: line)!]) ?? 0
                let col = Int(line[Range(match.range(at: 3), in: line)!])
                let severity = String(line[Range(match.range(at: 4), in: line)!])
                let message = String(line[Range(match.range(at: 5), in: line)!])

                if severity == "error" || severity == "warning" {
                    extractedFiles.append((file: file, line: lineNum, col: col))
                    suggestedCauses.append("\(severity): \(message) at \(file):\(lineNum)")
                }
            }
        }

        // Parse stack trace frames: N ModuleName 0xADDR functionName + offset
        let stackPattern = try? NSRegularExpression(pattern: #"^\d+\s+(\S+)\s+0x[0-9a-fA-F]+\s+(.+)\s*\+\s*\d+"#, options: .anchorsMatchLines)
        var stackFrames: [String] = []
        for line in lines {
            let range = NSRange(line.startIndex..., in: line)
            if let match = stackPattern?.firstMatch(in: line, range: range) {
                let module = String(line[Range(match.range(at: 1), in: line)!])
                let symbol = String(line[Range(match.range(at: 2), in: line)!])
                stackFrames.append("\(module): \(symbol)")
            }
        }
        if !stackFrames.isEmpty {
            analysis.append("## Stack Trace (\(stackFrames.count) frames)\n" + stackFrames.prefix(15).enumerated().map { "  #\($0.offset) \($0.element)" }.joined(separator: "\n"))
        }

        // Parse test assertion failures: XCTAssertEqual failed: ("A") is not equal to ("B")
        let assertPattern = try? NSRegularExpression(pattern: #"(XCT\w+)\s+failed[:\s]*(.+)"#)
        for line in lines {
            let range = NSRange(line.startIndex..., in: line)
            if let match = assertPattern?.firstMatch(in: line, range: range) {
                let assertType = String(line[Range(match.range(at: 1), in: line)!])
                let detail = String(line[Range(match.range(at: 2), in: line)!])
                suggestedCauses.append("Test \(assertType) failed: \(detail)")
            }
        }

        // Check if extracted files exist in workspace
        var existingFiles: [String] = []
        var missingFiles: [String] = []
        for extracted in extractedFiles {
            let fullPath = extracted.file.hasPrefix("/") ? extracted.file : workspace + "/" + extracted.file
            if FileManager.default.fileExists(atPath: fullPath) {
                existingFiles.append("\(extracted.file):\(extracted.line)")
            } else {
                missingFiles.append(extracted.file)
            }
        }

        if !extractedFiles.isEmpty {
            analysis.append("## Files Involved (\(extractedFiles.count))\n" + extractedFiles.map { "  - \($0.file):\($0.line)\($0.col != nil ? ":\($0.col!)" : "")" }.joined(separator: "\n"))
        }

        if !suggestedCauses.isEmpty {
            analysis.append("## Suggested Causes (\(suggestedCauses.count))\n" + suggestedCauses.enumerated().map { "  \($0.offset + 1). \($0.element)" }.joined(separator: "\n"))
        }

        if !existingFiles.isEmpty {
            analysis.append("## Files to Investigate\n" + existingFiles.map { "  - \($0)" }.joined(separator: "\n"))
        }

        if !extraContext.isEmpty {
            analysis.append("## Additional Context\n\(extraContext)")
        }

        await debugLogServer.log(
            severity: "info",
            source: "debug_trace_analyze",
            message: "Analyzed \(detectedType) error: \(extractedFiles.count) files, \(suggestedCauses.count) causes",
            detail: analysis.joined(separator: "\n\n"),
            category: "debug"
        )

        let ms = Int(Date().timeIntervalSince(startDate) * 1000)
        return ToolResult(ok: true, payload: [
            "title": "debug_trace_analyze",
            "detail": "\(detectedType): \(extractedFiles.count) files, \(suggestedCauses.count) causes, \(stackFrames.count) stack frames",
            "output": analysis.joined(separator: "\n\n"),
            "error_type": detectedType,
            "files_count": "\(extractedFiles.count)",
            "causes_count": "\(suggestedCauses.count)",
            "stack_frames": "\(stackFrames.count)"
        ], durationMs: ms)
    }

    // MARK: - debug_instrument: Insert intelligent executable instrumentation

    func executeDebugInstrument(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let rawPath = call.args["path"] ?? ""
        let lineStr = call.args["line"] ?? ""
        let requestedType = (call.args["type"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let instrType = requestedType.isEmpty ? "log" : requestedType
        let expression = call.args["expression"] ?? ""
        let condition = call.args["condition"] ?? ""
        let hypothesisId = call.args["hypothesis_id"] ?? ""
        let label = call.args["label"] ?? ""

        guard !rawPath.isEmpty else {
            return ToolResult(ok: false, payload: ["detail": "path is required"], durationMs: 0)
        }
        guard let lineNum = Int(lineStr), lineNum > 0 else {
            return ToolResult(ok: false, payload: ["detail": "valid line number is required"], durationMs: 0)
        }
        guard !expression.isEmpty else {
            return ToolResult(ok: false, payload: ["detail": "expression is required"], durationMs: 0)
        }
        let allowedTypes: Set<String> = ["log", "assert", "timing", "variable", "conditional_break"]
        let ms = Int(Date().timeIntervalSince(startDate) * 1000)
        guard allowedTypes.contains(instrType) else {
            return ToolResult(
                ok: false,
                payload: ["detail": "Unknown instrumentation type '\(instrType)'. Use: log, assert, timing, variable, conditional_break."],
                durationMs: ms
            )
        }

        let path: String
        do {
            path = try resolveRequiredPath(rawPath, context: context)
        } catch let err as ToolRuntimeError {
            return ToolResult(ok: false, payload: ["detail": err.localizedDescription], durationMs: 0)
        } catch {
            return ToolResult(ok: false, payload: ["detail": error.localizedDescription], durationMs: 0)
        }
        let hypTag = hypothesisId.isEmpty ? "" : " [H:\(hypothesisId.prefix(8))]"
        let labelTag = label.isEmpty ? "" : " [\(label)]"

        let generatedCode: String
        switch instrType {
        case "log":
            generatedCode = "print(\"\\u{1F50D} INSTRUMENT\(labelTag): \\(\(expression))\") // \u{1F41B} DEBUG[instrument-log]: \(label.isEmpty ? expression : label)\(hypTag)"
        case "assert":
            let msg = condition.isEmpty ? expression : condition
            generatedCode = "assert(\(expression), \"\\u{1F6A8} INSTRUMENT ASSERT\(labelTag): \(msg)\") // \u{1F41B} DEBUG[instrument-assert]: \(label.isEmpty ? expression : label)\(hypTag)"
        case "timing":
            let timerName = "_instrTimer_\(lineNum)"
            generatedCode = "let \(timerName) = CFAbsoluteTimeGetCurrent(); defer { print(\"\\u{23F1} INSTRUMENT TIMING\(labelTag): \\(String(format: \"%.4f\", CFAbsoluteTimeGetCurrent() - \(timerName)))s for \(expression)\") } // \u{1F41B} DEBUG[instrument-timing]: \(label.isEmpty ? expression : label)\(hypTag)"
        case "variable":
            generatedCode = "print(\"\\u{1F4CB} INSTRUMENT VAR\(labelTag) \(expression) = \\(\(expression)) [type: \\(type(of: \(expression)))]\") // \u{1F41B} DEBUG[instrument-variable]: \(label.isEmpty ? expression : label)\(hypTag)"
        case "conditional_break":
            let cond = condition.isEmpty ? "true" : condition
            generatedCode = "if \(cond) { print(\"\\u{1F6D1} INSTRUMENT BREAK\(labelTag): condition met — \(expression) = \\(\(expression))\") } // \u{1F41B} DEBUG[instrument-conditional]: \(label.isEmpty ? expression : label)\(hypTag)"
        default:
            // Guard above validates allowed values; this is a defensive fallback.
            generatedCode = "print(\"\\u{1F50D} INSTRUMENT\(labelTag): \\(\(expression))\") // \u{1F41B} DEBUG[instrument-log]: \(label.isEmpty ? expression : label)\(hypTag)"
        }

        do {
            let content = try String(contentsOfFile: path, encoding: .utf8)
            var lines = content.components(separatedBy: "\n")
            let insertIdx = min(lineNum, lines.count)

            lines.insert(generatedCode, at: insertIdx)
            try lines.joined(separator: "\n").write(toFile: path, atomically: true, encoding: String.Encoding.utf8)

            await debugLogServer.log(
                severity: "info",
                source: "debug_instrument",
                message: "[\(instrType)] Instrumented \((path as NSString).lastPathComponent):\(lineNum)\(labelTag)",
                detail: generatedCode,
                category: "instrumentation"
            )

            return ToolResult(ok: true, payload: [
                "title": "debug_instrument",
                "detail": "[\(instrType)] instrumented \((path as NSString).lastPathComponent):\(lineNum)",
                "output": "Inserted [\(instrType)] instrumentation at line \(lineNum):\n\(generatedCode)",
                "path": path,
                "line": "\(lineNum)",
                "type": instrType,
                "expression": expression,
                "hypothesis_id": hypothesisId,
                "label": label
            ], durationMs: ms)
        } catch {
            return ToolResult(ok: false, payload: [
                "title": "debug_instrument",
                "detail": "Failed to instrument: \(error.localizedDescription)"
            ], durationMs: ms)
        }
    }

    // MARK: - debug_timeline: Chronological event timeline

}
