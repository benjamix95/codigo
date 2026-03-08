import Foundation

extension UnifiedToolRuntime {
    func executeDebugSession(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let action = (call.args["action"] ?? "start").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let label = (call.args["label"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let ms = Int(Date().timeIntervalSince(startDate) * 1000)

        switch action {
        case "start":
            let sessionId = await debugLogServer.startSession()
            debugHypotheses.removeAll()
            debugSessionSnapshots.removeAll()
            debugFailingTestFilters.removeAll()
            debugSessionStartTime = Date()
            return ToolResult(ok: true, payload: [
                "title": "debug_session",
                "detail": "Debug session started (id: \(sessionId.prefix(8)))",
                "output": "Session \(sessionId) started",
                "action": "start",
                "session_id": sessionId
            ], durationMs: ms)

        case "end", "stop":
            let detail: String
            let summary: String
            if let activeSessionId = await debugLogServer.currentSessionId() {
                summary = await debugLogServer.sessionSummary(sessionId: activeSessionId)
                await debugLogServer.endSession()
                detail = "Debug session ended"
            } else {
                summary = "No active debug session."
                detail = "No active debug session"
            }
            debugSessionStartTime = nil
            return ToolResult(ok: true, payload: [
                "title": "debug_session",
                "detail": detail,
                "output": summary,
                "action": action
            ], durationMs: ms)

        case "clear":
            await debugLogServer.clearSession()
            debugHypotheses.removeAll()
            debugSessionSnapshots.removeAll()
            debugFailingTestFilters.removeAll()
            debugSessionStartTime = nil
            return ToolResult(ok: true, payload: [
                "title": "debug_session",
                "detail": "Session logs cleared",
                "output": "Session logs cleared",
                "action": "clear"
            ], durationMs: ms)

        case "snapshot":
            let snapshotLabel = label.isEmpty ? "snapshot-\(debugSessionSnapshots.count + 1)" : label
            let logResult = await debugLogServer.query(limit: 500)
            let hypothesesSummary = debugHypotheses.map { (id, h) in
                "\(id.prefix(8)): [\(h.status)] \(h.title) (\(h.confidence)%)"
            }.joined(separator: "\n")

            let snapshot: [String: String] = [
                "timestamp": ISO8601DateFormatter().string(from: Date()),
                "log_count": "\(logResult.totalCount)",
                "error_count": "\(logResult.errorCount)",
                "warning_count": "\(logResult.warningCount)",
                "hypothesis_count": "\(debugHypotheses.count)",
                "hypotheses": hypothesesSummary,
                "label": snapshotLabel
            ]
            debugSessionSnapshots[snapshotLabel] = snapshot

            return ToolResult(ok: true, payload: [
                "title": "debug_session",
                "detail": "Snapshot '\(snapshotLabel)' saved",
                "output": "Snapshot '\(snapshotLabel)': \(logResult.totalCount) logs, \(logResult.errorCount) errors, \(debugHypotheses.count) hypotheses",
                "action": "snapshot",
                "label": snapshotLabel,
                "snapshot_count": "\(debugSessionSnapshots.count)"
            ], durationMs: ms)

        case "export":
            let logResult = await debugLogServer.query(limit: 200)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withTime, .withColonSeparatorInTime]

            var md = "# Debug Session Report\n\n"
            if let start = debugSessionStartTime {
                let duration = Int(Date().timeIntervalSince(start))
                md += "**Duration**: \(duration / 60)m \(duration % 60)s\n\n"
            }

            md += "## Hypotheses (\(debugHypotheses.count))\n\n"
            for (id, h) in debugHypotheses.sorted(by: { $0.value.confidence > $1.value.confidence }) {
                md += "### \(h.title)\n"
                md += "- ID: `\(id.prefix(8))`\n"
                md += "- Status: **\(h.status)** | Confidence: \(h.confidence)%\n"
                if !h.rootCauseType.isEmpty { md += "- Type: \(h.rootCauseType)\n" }
                if !h.relatedFiles.isEmpty { md += "- Files: \(h.relatedFiles.joined(separator: ", "))\n" }
                if !h.description.isEmpty { md += "- \(h.description)\n" }
                md += "\n"
            }

            md += "## Log Summary\n\n"
            md += "- Total: \(logResult.totalCount)\n"
            md += "- Errors: \(logResult.errorCount)\n"
            md += "- Warnings: \(logResult.warningCount)\n\n"

            if !logResult.entries.isEmpty {
                md += "## Recent Logs\n\n"
                for entry in logResult.entries.suffix(50) {
                    let ts = formatter.string(from: entry.timestamp)
                    md += "- `[\(ts)]` **\(entry.severity.uppercased())** \(entry.source): \(entry.message)\n"
                }
            }

            return ToolResult(ok: true, payload: [
                "title": "debug_session",
                "detail": "Session exported as markdown",
                "output": md,
                "action": "export"
            ], durationMs: ms)

        case "stats":
            let logResult = await debugLogServer.query(limit: 1)
            var stats = "## Session Statistics\n\n"
            if let start = debugSessionStartTime {
                let duration = Int(Date().timeIntervalSince(start))
                stats += "Duration: \(duration / 60)m \(duration % 60)s\n"
            }
            stats += "Total logs: \(logResult.totalCount)\n"
            stats += "Errors: \(logResult.errorCount)\n"
            stats += "Warnings: \(logResult.warningCount)\n"
            stats += "Hypotheses: \(debugHypotheses.count)\n"

            let statusCounts = Dictionary(grouping: debugHypotheses.values, by: \.status).mapValues(\.count)
            for (status, count) in statusCounts.sorted(by: { $0.key < $1.key }) {
                stats += "  - \(status): \(count)\n"
            }
            stats += "Snapshots: \(debugSessionSnapshots.count)\n"

            return ToolResult(ok: true, payload: [
                "title": "debug_session",
                "detail": "Session stats: \(logResult.totalCount) logs, \(debugHypotheses.count) hypotheses",
                "output": stats,
                "action": "stats"
            ], durationMs: ms)

        default:
            return ToolResult(ok: false, payload: ["detail": "Unknown action: \(action). Use start, end, stop, clear, snapshot, export, or stats."], durationMs: ms)
        }
    }

    func executeDebugHypothesize(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let title = (call.args["title"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let description = (call.args["description"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let action = (call.args["action"] ?? "propose").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hypothesisId = (call.args["hypothesis_id"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedStatus = (call.args["status"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let evidence = call.args["evidence"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let confidence = Int(call.args["confidence"] ?? "") ?? -1
        let rootCauseType = (call.args["root_cause_type"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let relatedFiles = (call.args["related_files"] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let relatedTests = (call.args["related_tests"] ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        let ms = Int(Date().timeIntervalSince(startDate) * 1000)

        switch action {
        case "propose":
            guard !title.isEmpty else {
                return ToolResult(ok: false, payload: ["detail": "title is required for propose action"], durationMs: ms)
            }

            let newHypothesisId = UUID().uuidString
            let normalizedStatus = normalizeHypothesisStatus(requestedStatus, fallback: "proposed")
            let clampedConfidence = confidence >= 0 ? min(max(confidence, 0), 100) : 50

            debugHypotheses[newHypothesisId] = DebugHypothesis(
                title: title,
                description: description,
                status: normalizedStatus,
                confidence: clampedConfidence,
                rootCauseType: rootCauseType,
                relatedFiles: relatedFiles,
                relatedTests: relatedTests,
                evidence: evidence != nil ? [evidence!] : [],
                createdAt: Date()
            )

            var logDetail = description
            if !rootCauseType.isEmpty { logDetail += "\nType: \(rootCauseType)" }
            if !relatedFiles.isEmpty { logDetail += "\nFiles: \(relatedFiles.joined(separator: ", "))" }

            await debugLogServer.log(
                severity: "info",
                source: "hypothesis",
                message: "Hypothesis \(newHypothesisId.prefix(8)) proposed: \(title) [confidence: \(clampedConfidence)%]",
                detail: logDetail,
                category: "debug"
            )

            var output = "Proposed hypothesis \(newHypothesisId.prefix(8)): \(title)\n"
            output += "  Status: \(normalizedStatus)\n"
            output += "  Confidence: \(clampedConfidence)%\n"
            if !rootCauseType.isEmpty { output += "  Root cause type: \(rootCauseType)\n" }
            if !relatedFiles.isEmpty { output += "  Related files: \(relatedFiles.joined(separator: ", "))\n" }
            if !relatedTests.isEmpty { output += "  Related tests: \(relatedTests.joined(separator: ", "))\n" }

            return ToolResult(ok: true, payload: [
                "title": "debug_hypothesize",
                "detail": "Hypothesis proposed: \(title) [\(clampedConfidence)%]",
                "output": output,
                "action": "propose",
                "hypothesis_id": newHypothesisId,
                "hypothesis_title": title,
                "description": description,
                "hypothesis_status": normalizedStatus,
                "confidence": "\(clampedConfidence)",
                "root_cause_type": rootCauseType,
                "related_files": relatedFiles.joined(separator: ","),
                "evidence": evidence ?? ""
            ], durationMs: ms)

        case "update":
            guard !hypothesisId.isEmpty else {
                return ToolResult(ok: false, payload: ["detail": "hypothesis_id is required for update"], durationMs: ms)
            }
            let resolvedHypothesisId: String
            switch resolveHypothesisLookup(hypothesisId) {
            case .resolved(let id):
                resolvedHypothesisId = id
            case .ambiguous(let prefixes):
                return ToolResult(
                    ok: false,
                    payload: ["detail": "Ambiguous hypothesis_id prefix '\(hypothesisId)'. Matches: \(prefixes.joined(separator: ", "))"],
                    durationMs: ms
                )
            case .notFound:
                return ToolResult(ok: false, payload: ["detail": "Unknown hypothesis_id: \(hypothesisId)"], durationMs: ms)
            }
            guard var existing = debugHypotheses[resolvedHypothesisId] else {
                return ToolResult(ok: false, payload: ["detail": "Unknown hypothesis_id: \(hypothesisId)"], durationMs: ms)
            }

            let nextStatus = normalizeHypothesisStatus(requestedStatus, fallback: existing.status)
            existing.status = nextStatus
            if confidence >= 0 { existing.confidence = min(max(confidence, 0), 100) }
            if !rootCauseType.isEmpty { existing.rootCauseType = rootCauseType }
            if !relatedFiles.isEmpty { existing.relatedFiles = relatedFiles }
            if !relatedTests.isEmpty { existing.relatedTests = relatedTests }
            if let evidence { existing.evidence.append(evidence) }
            debugHypotheses[resolvedHypothesisId] = existing

            await debugLogServer.log(
                severity: "info",
                source: "hypothesis",
                message: "Hypothesis \(resolvedHypothesisId.prefix(8)) updated to \(nextStatus) [confidence: \(existing.confidence)%]",
                detail: evidence,
                category: "debug"
            )

            var output = "Updated hypothesis \(resolvedHypothesisId.prefix(8)) -> \(nextStatus)\n"
            output += "  Title: \(existing.title)\n"
            output += "  Confidence: \(existing.confidence)%\n"
            if !existing.rootCauseType.isEmpty { output += "  Root cause type: \(existing.rootCauseType)\n" }
            if !existing.relatedFiles.isEmpty { output += "  Related files: \(existing.relatedFiles.joined(separator: ", "))\n" }
            if existing.evidence.count > 1 { output += "  Evidence entries: \(existing.evidence.count)\n" }

            return ToolResult(ok: true, payload: [
                "title": "debug_hypothesize",
                "detail": "Hypothesis updated to \(nextStatus) [\(existing.confidence)%]",
                "output": output,
                "action": "update",
                "hypothesis_id": resolvedHypothesisId,
                "hypothesis_title": existing.title,
                "description": existing.description,
                "hypothesis_status": nextStatus,
                "confidence": "\(existing.confidence)",
                "root_cause_type": existing.rootCauseType,
                "related_files": existing.relatedFiles.joined(separator: ","),
                "evidence": evidence ?? ""
            ], durationMs: ms)

        default:
            return ToolResult(ok: false, payload: ["detail": "Unknown action: \(action). Use propose or update."], durationMs: ms)
        }
    }

    // MARK: - debug_mark: Insert a typed debug marker/instrumentation into a file

}
