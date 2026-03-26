import Foundation

extension UnifiedToolRuntime {
    func executeDebugTimeline(call: ToolCall, context _: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let filterRaw = (call.args["filter"] ?? "all").lowercased()
        let filters = Set(filterRaw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        let showAll = filters.contains("all")
        let timeRange = call.args["time_range"]
        let hypothesisId = call.args["hypothesis_id"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let format = (call.args["format"] ?? "text").lowercased()

        let allEntries = await debugLogServer.allEntries()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withTime, .withColonSeparatorInTime]

        var events: [(date: Date, type: String, text: String)] = []

        // Collect log events
        if showAll || filters.contains("logs") {
            for entry in allEntries {
                if !entryMatchesHypothesis(entry, filter: hypothesisId) {
                    continue
                }
                let cat = entry.category ?? "log"
                events.append((date: entry.timestamp, type: "log[\(cat)]", text: "[\(entry.severity.uppercased())] \(entry.source): \(entry.message)"))
            }
        }

        // Collect phase changes
        if showAll || filters.contains("phases") {
            for entry in allEntries where entry.category == "system" {
                events.append((date: entry.timestamp, type: "phase", text: entry.message))
            }
        }

        // Collect hypotheses events
        if showAll || filters.contains("hypotheses") {
            for entry in allEntries where entry.category == "debug" && entry.source == "hypothesis" {
                if !entryMatchesHypothesis(entry, filter: hypothesisId) {
                    continue
                }
                events.append((date: entry.timestamp, type: "hypothesis", text: entry.message))
            }
        }

        // Collect marker events
        if showAll || filters.contains("markers") {
            for entry in allEntries where entry.source == "debug_mark" || entry.source == "debug_instrument" {
                if !entryMatchesHypothesis(entry, filter: hypothesisId) {
                    continue
                }
                events.append((date: entry.timestamp, type: "marker", text: entry.message))
            }
        }

        // Filter by time range
        if let timeRange, let minutes = Double(timeRange), minutes > 0 {
            let cutoff = Date().addingTimeInterval(-minutes * 60)
            events = events.filter { $0.date > cutoff }
        }

        events.sort { $0.date < $1.date }

        let ms = Int(Date().timeIntervalSince(startDate) * 1000)

        if events.isEmpty {
            return ToolResult(ok: true, payload: [
                "title": "debug_timeline",
                "detail": "No events found",
                "output": "No debug events match the filter criteria.",
                "event_count": "0"
            ], durationMs: ms)
        }

        let output: String
        if format == "mermaid" {
            var mermaid = "gantt\n    title Debug Timeline\n    dateFormat HH:mm:ss\n"
            for (i, event) in events.prefix(30).enumerated() {
                let ts = formatter.string(from: event.date)
                let safeText = event.text.prefix(40).replacingOccurrences(of: ":", with: "-")
                mermaid += "    \(event.type) \(i + 1) - \(safeText) : \(ts), 1s\n"
            }
            output = mermaid
        } else {
            var lines: [String] = ["## Debug Timeline (\(events.count) events)\n"]
            for event in events {
                let ts = formatter.string(from: event.date)
                let icon: String
                switch event.type {
                case "phase": icon = "🔄"
                case "hypothesis": icon = "💡"
                case "marker": icon = "📌"
                default: icon = "📝"
                }
                lines.append("  \(ts) \(icon) [\(event.type)] \(event.text)")
            }
            output = lines.joined(separator: "\n")
        }

        return ToolResult(ok: true, payload: [
            "title": "debug_timeline",
            "detail": "\(events.count) events (\(filterRaw))",
            "output": output,
            "event_count": "\(events.count)",
            "format": format
        ], durationMs: ms)
    }

    // MARK: - debug_snapshot: Capture and compare session state

    func executeDebugSnapshot(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let action = (call.args["action"] ?? "capture").lowercased()
        let label = (call.args["label"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let compareWith = (call.args["compare_with"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let ms = Int(Date().timeIntervalSince(startDate) * 1000)

        switch action {
        case "capture":
            let snapshotLabel = label.isEmpty ? "snap-\(debugSessionSnapshots.count + 1)" : label
            let logResult = await debugLogServer.query(limit: 500)

            let hypothesesData = debugHypotheses.map { (id, h) in
                "\(id.prefix(8))|[\(h.status)]\(h.title)|\(h.confidence)%"
            }.joined(separator: "\n")

            let snapshot: [String: String] = [
                "timestamp": ISO8601DateFormatter().string(from: Date()),
                "log_count": "\(logResult.totalCount)",
                "error_count": "\(logResult.errorCount)",
                "warning_count": "\(logResult.warningCount)",
                "hypothesis_count": "\(debugHypotheses.count)",
                "hypotheses": hypothesesData,
                "confirmed_count": "\(debugHypotheses.values.filter { $0.status == "confirmed" }.count)",
                "rejected_count": "\(debugHypotheses.values.filter { $0.status == "rejected" }.count)",
                "label": snapshotLabel
            ]
            debugSessionSnapshots[snapshotLabel] = snapshot

            var output = "## Snapshot '\(snapshotLabel)' captured\n\n"
            output += "- Logs: \(logResult.totalCount) (\(logResult.errorCount) errors, \(logResult.warningCount) warnings)\n"
            output += "- Hypotheses: \(debugHypotheses.count)\n"
            for (id, h) in debugHypotheses {
                output += "  - \(id.prefix(8)): [\(h.status)] \(h.title) (\(h.confidence)%)\n"
            }

            return ToolResult(ok: true, payload: [
                "title": "debug_snapshot",
                "detail": "Snapshot '\(snapshotLabel)' captured",
                "output": output,
                "action": "capture",
                "label": snapshotLabel,
                "snapshot_count": "\(debugSessionSnapshots.count)"
            ], durationMs: ms)

        case "compare":
            guard !label.isEmpty else {
                return ToolResult(ok: false, payload: ["detail": "label is required for compare (snapshot label or name for the newer side)"], durationMs: ms)
            }
            guard !compareWith.isEmpty else {
                return ToolResult(ok: false, payload: ["detail": "compare_with is required (baseline snapshot label)"], durationMs: ms)
            }
            guard let snapBaseline = debugSessionSnapshots[compareWith] else {
                return ToolResult(ok: false, payload: ["detail": "Snapshot '\(compareWith)' not found. Available: \(debugSessionSnapshots.keys.sorted().joined(separator: ", "))"], durationMs: ms)
            }

            // Due snapshot persistiti: confronto etichettato vs etichettato (semantica stabile).
            if let snapOther = debugSessionSnapshots[label] {
                var diff = "## Snapshot comparison (persisted): '\(compareWith)' vs '\(label)'\n\n"
                let fields = ["log_count", "error_count", "warning_count", "hypothesis_count", "confirmed_count", "rejected_count"]
                for field in fields {
                    let a = Int(snapBaseline[field] ?? "0") ?? 0
                    let b = Int(snapOther[field] ?? "0") ?? 0
                    let delta = b - a
                    let arrow = delta > 0 ? "↑\(delta)" : (delta < 0 ? "↓\(abs(delta))" : "→")
                    diff += "- \(field): \(a) \(arrow) \(b)\n"
                }
                diff += "\n- Time: \(snapBaseline["timestamp"] ?? "?") vs \(snapOther["timestamp"] ?? "?")\n"
                return ToolResult(ok: true, payload: [
                    "title": "debug_snapshot",
                    "detail": "Compared persisted '\(compareWith)' with '\(label)'",
                    "output": diff,
                    "action": "compare",
                    "compare_mode": "persisted_pair",
                ], durationMs: ms)
            }

            // Fallback: confronta baseline persistito con lo stato sessione corrente (etichetta `label` è solo nome report).
            let logResult = await debugLogServer.query(limit: 1)
            let snapCurrent: [String: String] = [
                "timestamp": ISO8601DateFormatter().string(from: Date()),
                "log_count": "\(logResult.totalCount)",
                "error_count": "\(logResult.errorCount)",
                "warning_count": "\(logResult.warningCount)",
                "hypothesis_count": "\(debugHypotheses.count)",
                "confirmed_count": "\(debugHypotheses.values.filter { $0.status == "confirmed" }.count)",
                "rejected_count": "\(debugHypotheses.values.filter { $0.status == "rejected" }.count)",
                "label": label
            ]

            var diff = "## Snapshot comparison: '\(compareWith)' (saved) → current session (as '\(label)')\n\n"
            let fields = ["log_count", "error_count", "warning_count", "hypothesis_count", "confirmed_count", "rejected_count"]
            for field in fields {
                let a = Int(snapBaseline[field] ?? "0") ?? 0
                let b = Int(snapCurrent[field] ?? "0") ?? 0
                let delta = b - a
                let arrow = delta > 0 ? "↑\(delta)" : (delta < 0 ? "↓\(abs(delta))" : "→")
                diff += "- \(field): \(a) \(arrow) \(b)\n"
            }
            diff += "\n- Time: \(snapBaseline["timestamp"] ?? "?") -> \(snapCurrent["timestamp"] ?? "?")\n"

            return ToolResult(ok: true, payload: [
                "title": "debug_snapshot",
                "detail": "Compared '\(compareWith)' with current session state",
                "output": diff,
                "action": "compare",
                "compare_mode": "baseline_to_current",
            ], durationMs: ms)

        case "list":
            if debugSessionSnapshots.isEmpty {
                return ToolResult(ok: true, payload: [
                    "title": "debug_snapshot",
                    "detail": "No snapshots available",
                    "output": "No snapshots have been captured yet. Use action=capture to save one.",
                    "action": "list"
                ], durationMs: ms)
            }

            var output = "## Available Snapshots (\(debugSessionSnapshots.count))\n\n"
            for (snapLabel, data) in debugSessionSnapshots.sorted(by: { ($0.value["timestamp"] ?? "") < ($1.value["timestamp"] ?? "") }) {
                output += "- **\(snapLabel)** (\(data["timestamp"] ?? "?")): \(data["log_count"] ?? "0") logs, \(data["hypothesis_count"] ?? "0") hypotheses\n"
            }

            return ToolResult(ok: true, payload: [
                "title": "debug_snapshot",
                "detail": "\(debugSessionSnapshots.count) snapshots available",
                "output": output,
                "action": "list"
            ], durationMs: ms)

        default:
            return ToolResult(ok: false, payload: ["detail": "Unknown action: \(action). Use capture, compare, or list."], durationMs: ms)
        }
    }

    // MARK: - debug_test_check: Targeted test verification

}
