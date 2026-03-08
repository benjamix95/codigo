import Foundation

extension UnifiedToolRuntime {
    func executeDebugQuery(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let severity = call.args["severity"]
        let category = call.args["category"]
        let source = call.args["source"]
        let search = call.args["search"] ?? call.args["query"]
        let tags = call.args["tags"]
        let hypothesisId = call.args["hypothesis_id"]
        let sessionId = call.args["session_id"] ?? call.args["sessionId"]
        let timeRange = call.args["time_range"]
        let groupBy = call.args["group_by"]
        let requestedLimit = Int(call.args["limit"] ?? "50") ?? 50
        let limit = min(max(requestedLimit, 1), 500)
        let offset = max(0, Int(call.args["offset"] ?? "0") ?? 0)
        let format = (call.args["format"] ?? "summary").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cutoff: Date? = {
            guard let timeRange, let minutes = Double(timeRange), minutes > 0 else { return nil }
            return Date().addingTimeInterval(-minutes * 60)
        }()

        if format == "summary",
           severity == nil, category == nil, source == nil, tags == nil, hypothesisId == nil,
           sessionId == nil, cutoff == nil, offset == 0,
           (search?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
            let summary = await debugLogServer.sessionSummary()
            let ms = Int(Date().timeIntervalSince(startDate) * 1000)
            return ToolResult(ok: true, payload: [
                "title": "debug_query",
                "detail": "Debug session summary",
                "output": summary,
                "format": "summary"
            ], durationMs: ms)
        }

        var result = await debugLogServer.query(
            severity: severity,
            category: category,
            source: source,
            search: search,
            sessionId: sessionId,
            limit: limit,
            offset: offset,
            after: cutoff
        )

        // Post-filter by tags
        if let tags, !tags.isEmpty {
            let tagSet = Set(
                tags
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                    .filter { !$0.isEmpty }
            )
            result = result.filtered { entry in
                let entryTags = Set(extractTags(from: entry).map { $0.lowercased() })
                return !entryTags.isEmpty && !entryTags.isDisjoint(with: tagSet)
            }
        }

        // Post-filter by hypothesis_id
        if let hypothesisId, !hypothesisId.isEmpty {
            result = result.filteredByHypothesisId(hypothesisId)
        }

        // Group-by aggregation
        if let groupBy, !groupBy.isEmpty {
            let output = buildGroupByOutput(result: result, groupBy: groupBy)
            let ms = Int(Date().timeIntervalSince(startDate) * 1000)
            return ToolResult(ok: true, payload: [
                "title": "debug_query (grouped)",
                "detail": "Grouped by \(groupBy): \(result.totalCount) entries",
                "output": output,
                "format": "grouped",
                "group_by": groupBy
            ], durationMs: ms)
        }

        let output: String
        switch format {
        case "json":
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            let jsonEntries = result.entries.map { entry -> [String: String] in
                var e: [String: String] = [
                    "timestamp": formatter.string(from: entry.timestamp),
                    "severity": entry.severity,
                    "source": entry.source,
                    "message": entry.message
                ]
                if let d = entry.detail { e["detail"] = d }
                if let c = entry.category { e["category"] = c }
                return e
            }
            if let jsonData = try? JSONSerialization.data(withJSONObject: jsonEntries, options: [.prettyPrinted, .sortedKeys]),
               let jsonStr = String(data: jsonData, encoding: .utf8) {
                output = jsonStr
            } else {
                output = "Failed to serialize to JSON"
            }
        case "markdown":
            var md = "# Debug Log Report\n\n"
            md += "| Time | Severity | Source | Message |\n|------|----------|--------|---------|\n"
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withTime, .withColonSeparatorInTime]
            for entry in result.entries {
                let ts = formatter.string(from: entry.timestamp)
                md += "| \(ts) | \(entry.severity.uppercased()) | \(entry.source) | \(entry.message) |\n"
            }
            md += "\n**Total**: \(result.totalCount), **Errors**: \(result.errorCount), **Warnings**: \(result.warningCount)"
            output = md
        case "summary":
            output = """
            Debug Query Summary:
              Total entries: \(result.totalCount)
              Errors: \(result.errorCount)
              Warnings: \(result.warningCount)
            """
        default:
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withTime, .withColonSeparatorInTime]
            output = result.entries.isEmpty
                ? "No log entries matched the query."
                : result.entries.map { entry in
                    let ts = formatter.string(from: entry.timestamp)
                    let cat = entry.category.map { "[\($0)] " } ?? ""
                    let detail = entry.detail.map { "\n  detail: \($0)" } ?? ""
                    return "[\(ts)] \(entry.severity.uppercased()) \(cat)\(entry.source): \(entry.message)\(detail)"
                }.joined(separator: "\n")
        }

        let ms = Int(Date().timeIntervalSince(startDate) * 1000)
        return ToolResult(ok: true, payload: [
            "title": "debug_query",
            "detail": "\(result.totalCount) entries (\(result.errorCount) errors, \(result.warningCount) warnings)",
            "output": output,
            "format": format
        ], durationMs: ms)
    }

    func buildGroupByOutput(result: DebugLogServer.QueryResult, groupBy: String) -> String {
        var groups: [String: Int] = [:]
        for entry in result.entries {
            switch groupBy.lowercased() {
            case "severity":
                groups[entry.severity, default: 0] += 1
            case "source":
                groups[entry.source, default: 0] += 1
            case "category":
                groups[entry.category ?? "(none)", default: 0] += 1
            case "tags":
                let tags = extractTags(from: entry)
                if tags.isEmpty {
                    groups["(none)", default: 0] += 1
                } else {
                    for tag in tags {
                        groups[tag, default: 0] += 1
                    }
                }
            default:
                groups[entry.severity, default: 0] += 1
            }
        }
        let sorted = groups.sorted { $0.value > $1.value }
        var lines = ["## Group by: \(groupBy) (\(result.totalCount) total)"]
        for (key, count) in sorted {
            let bar = String(repeating: "█", count: min(count, 40))
            lines.append("  \(key): \(count) \(bar)")
        }
        return lines.joined(separator: "\n")
    }

    func extractTags(from entry: DebugLogServer.LogEntry) -> [String] {
        let candidates = [entry.detail, entry.message].compactMap { $0 }
        for text in candidates {
            for line in text.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard trimmed.lowercased().hasPrefix("tags:") else { continue }
                let value = String(trimmed.dropFirst("tags:".count))
                let tags = value
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                    .filter { !$0.isEmpty }
                if !tags.isEmpty {
                    return tags
                }
            }
        }
        return []
    }

}
