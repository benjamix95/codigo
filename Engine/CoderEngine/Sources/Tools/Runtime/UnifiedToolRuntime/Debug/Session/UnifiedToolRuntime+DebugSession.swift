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
                for entry in logResult.entries.suffix(200) {
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

}
