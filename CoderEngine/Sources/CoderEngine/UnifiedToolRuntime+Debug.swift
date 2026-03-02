import Foundation

extension UnifiedToolRuntime {
    func parseDebugDataArg(_ raw: String?) -> [String: String] {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [:] }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{"),
           let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            var out: [String: String] = [:]
            for (key, value) in json { out[key] = "\(value)" }
            return out
        }
        var out: [String: String] = [:]
        for pair in raw.split(separator: ",") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2 {
                out[kv[0].trimmingCharacters(in: .whitespacesAndNewlines)] = kv[1].trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return out
    }

    func parseDebugDataValue(_ value: Any?) -> [String: String] {
        guard let value else { return [:] }
        if let stringValue = value as? String {
            return parseDebugDataArg(stringValue)
        }
        if let dict = value as? [String: String] {
            return dict
        }
        if let dict = value as? [String: Any] {
            var out: [String: String] = [:]
            for (key, raw) in dict {
                out[key] = String(describing: raw)
            }
            return out
        }
        return [:]
    }

    func enrichedDebugDetail(detail: String?, stackTrace: String?, tags: String?) -> String? {
        var parts: [String] = []
        if let detail, !detail.isEmpty {
            parts.append(detail)
        }
        if let stackTrace, !stackTrace.isEmpty {
            parts.append("Stack Trace:\n\(stackTrace)")
        }
        if let tags, !tags.isEmpty {
            parts.append("Tags: \(tags)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }

    func resolveHypothesisLookup(_ rawIdentifier: String) -> HypothesisLookupResult {
        let normalized = rawIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return .notFound }

        if let exact = debugHypotheses.keys.first(where: { $0.lowercased() == normalized }) {
            return .resolved(exact)
        }

        let short = String(normalized.prefix(8))
        let candidates = debugHypotheses.keys.filter { hypothesisID in
            let normalizedExisting = hypothesisID.lowercased()
            return normalizedExisting.hasPrefix(normalized)
                || String(normalizedExisting.prefix(8)) == short
        }

        if candidates.count == 1, let only = candidates.first {
            return .resolved(only)
        }
        if candidates.count > 1 {
            let prefixes = Array(Set(candidates.map { String($0.prefix(8)) })).sorted()
            return .ambiguous(prefixes)
        }
        return .notFound
    }

    func entryMatchesHypothesis(_ entry: DebugLogServer.LogEntry, filter hypothesisId: String?) -> Bool {
        let normalizedFilter = (hypothesisId ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalizedFilter.isEmpty else { return true }

        let short = String(normalizedFilter.prefix(8))
        let entryHypothesis = (entry.hypothesisId ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if !entryHypothesis.isEmpty {
            if entryHypothesis == normalizedFilter {
                return true
            }
            if String(entryHypothesis.prefix(8)) == short {
                return true
            }
        }

        let detail = (entry.detail ?? "").lowercased()
        let message = entry.message.lowercased()
        return detail.contains(normalizedFilter)
            || message.contains(normalizedFilter)
            || detail.contains("[h:\(short)]")
            || message.contains("[h:\(short)]")
            || message.contains(short)
    }

    func normalizeHypothesisStatus(_ status: String, fallback: String) -> String {
        switch status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "proposed", "investigating", "confirmed", "rejected":
            return status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        default:
            return fallback
        }
    }

    func executeDebugLog(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        // Batch mode: log multiple entries at once
        if let batchJSON = call.args["batch"], !batchJSON.isEmpty {
            return await executeDebugLogBatch(batchJSON: batchJSON, call: call, startDate: startDate)
        }

        let severity = call.args["severity"] ?? "info"
        let source = call.args["source"] ?? "agent"
        let message = call.args["message"] ?? ""
        let detail = call.args["detail"]
        let category = call.args["category"]
        let tags = call.args["tags"]
        let stackTrace = call.args["stack_trace"]
        let data = call.args["data"]
        let runId = call.args["run_id"] ?? call.args["runId"]
        let hypothesisId = call.args["hypothesis_id"] ?? call.args["hypothesisId"]
        let normalizedCategory = category?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        guard !message.isEmpty else {
            return ToolResult(ok: false, payload: ["detail": "message is required"], durationMs: 0)
        }

        let enrichedDetail = enrichedDebugDetail(detail: detail, stackTrace: stackTrace, tags: tags)

        if let category = normalizedCategory, category == "runtime" || category == "instrumentation" {
            await debugLogServer.logRuntime(
                source: source,
                message: message,
                severity: severity,
                detail: enrichedDetail,
                category: category,
                data: parseDebugDataArg(data),
                runId: runId,
                hypothesisId: hypothesisId
            )
        } else {
            await debugLogServer.log(
                severity: severity,
                source: source,
                message: message,
                detail: enrichedDetail,
                category: normalizedCategory,
                runId: runId,
                hypothesisId: hypothesisId,
                data: parseDebugDataArg(data)
            )
        }

        let ms = Int(Date().timeIntervalSince(startDate) * 1000)
        return ToolResult(ok: true, payload: [
            "title": "debug_log",
            "detail": "[\(severity.uppercased())] \(message)",
            "output": "Logged: [\(severity)] \(source): \(message)\(tags != nil ? " [tags: \(tags!)]" : "")\(hypothesisId != nil ? " [hypothesis: \(hypothesisId!)]" : "")",
            "severity": severity,
            "source": source,
            "message": message,
            "log_detail": enrichedDetail ?? "",
            "category": normalizedCategory ?? "",
            "tags": tags ?? "",
            "stack_trace": stackTrace ?? "",
            "data": data ?? "",
            "run_id": runId ?? "",
            "hypothesis_id": hypothesisId ?? ""
        ], durationMs: ms)
    }

    func executeDebugLogBatch(batchJSON: String, call _: ToolCall, startDate: Date) async -> ToolResult {
        guard let jsonData = batchJSON.data(using: .utf8),
              let entries = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else {
            return ToolResult(ok: false, payload: ["detail": "batch must be a JSON array of log entries: [{severity, source, message, ...}]"], durationMs: 0)
        }

        var logged = 0
        for entry in entries {
            let sev = (entry["severity"] as? String) ?? "info"
            let src = (entry["source"] as? String) ?? "agent"
            let msg = (entry["message"] as? String) ?? ""
            let det = entry["detail"] as? String
            let cat = (entry["category"] as? String)
            let tags = entry["tags"] as? String
            let stackTrace = (entry["stack_trace"] as? String) ?? (entry["stackTrace"] as? String)
            let runId = (entry["run_id"] as? String) ?? (entry["runId"] as? String)
            let hypothesisId = (entry["hypothesis_id"] as? String) ?? (entry["hypothesisId"] as? String)
            guard !msg.isEmpty else { continue }
            let enrichedDetail = enrichedDebugDetail(detail: det, stackTrace: stackTrace, tags: tags)
            let normalizedCategory = cat?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            if let category = normalizedCategory, category == "runtime" || category == "instrumentation" {
                await debugLogServer.logRuntime(
                    source: src,
                    message: msg,
                    severity: sev,
                    detail: enrichedDetail,
                    category: category,
                    data: parseDebugDataValue(entry["data"]),
                    runId: runId,
                    hypothesisId: hypothesisId
                )
            } else {
                await debugLogServer.log(
                    severity: sev,
                    source: src,
                    message: msg,
                    detail: enrichedDetail,
                    category: normalizedCategory,
                    runId: runId,
                    hypothesisId: hypothesisId,
                    data: parseDebugDataValue(entry["data"])
                )
            }
            logged += 1
        }

        let ms = Int(Date().timeIntervalSince(startDate) * 1000)
        return ToolResult(ok: true, payload: [
            "title": "debug_log (batch)",
            "detail": "Batch logged \(logged) entries",
            "output": "Batch logged \(logged)/\(entries.count) entries",
            "logged_count": "\(logged)",
            "total_count": "\(entries.count)"
        ], durationMs: ms)
    }

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
                return ToolResult(ok: false, payload: ["detail": "label is required for compare (current snapshot label)"], durationMs: ms)
            }
            guard !compareWith.isEmpty else {
                return ToolResult(ok: false, payload: ["detail": "compare_with is required (previous snapshot label)"], durationMs: ms)
            }
            guard let snapA = debugSessionSnapshots[compareWith] else {
                return ToolResult(ok: false, payload: ["detail": "Snapshot '\(compareWith)' not found. Available: \(debugSessionSnapshots.keys.sorted().joined(separator: ", "))"], durationMs: ms)
            }

            // Capture current state as snapB
            let logResult = await debugLogServer.query(limit: 1)
            let snapB: [String: String] = [
                "timestamp": ISO8601DateFormatter().string(from: Date()),
                "log_count": "\(logResult.totalCount)",
                "error_count": "\(logResult.errorCount)",
                "warning_count": "\(logResult.warningCount)",
                "hypothesis_count": "\(debugHypotheses.count)",
                "confirmed_count": "\(debugHypotheses.values.filter { $0.status == "confirmed" }.count)",
                "rejected_count": "\(debugHypotheses.values.filter { $0.status == "rejected" }.count)",
                "label": label
            ]

            var diff = "## Snapshot Comparison: '\(compareWith)' -> '\(label)'\n\n"
            let fields = ["log_count", "error_count", "warning_count", "hypothesis_count", "confirmed_count", "rejected_count"]
            for field in fields {
                let a = Int(snapA[field] ?? "0") ?? 0
                let b = Int(snapB[field] ?? "0") ?? 0
                let delta = b - a
                let arrow = delta > 0 ? "↑\(delta)" : (delta < 0 ? "↓\(abs(delta))" : "→")
                diff += "- \(field): \(a) \(arrow) \(b)\n"
            }
            diff += "\n- Time: \(snapA["timestamp"] ?? "?") -> \(snapB["timestamp"] ?? "?")\n"

            return ToolResult(ok: true, payload: [
                "title": "debug_snapshot",
                "detail": "Compared '\(compareWith)' with current state",
                "output": diff,
                "action": "compare"
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

    func executeDebugTestCheck(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let scope = (call.args["scope"] ?? "related").lowercased()
        let rawPath = call.args["path"] ?? ""
        let filter = call.args["filter"] ?? ""
        let hypothesisId = call.args["hypothesis_id"] ?? ""
        let timeoutMs = Int(call.args["timeout_ms"] ?? "60000") ?? 60000
        let workspace = context.workspaceContext.workspacePath.path
        let packageSwift = (workspace as NSString).appendingPathComponent("Package.swift")
        if !FileManager.default.fileExists(atPath: packageSwift) {
            let ms = Int(Date().timeIntervalSince(startDate) * 1000)
            return ToolResult(ok: false, payload: [
                "title": "debug_test_check",
                "detail": "debug_test_check currently supports Swift Package projects only",
                "output": "No Package.swift found in workspace. Use language-specific test tooling for non-Swift projects.",
                "scope": scope,
                "error_code": "validation"
            ], durationMs: ms)
        }

        var testArgs: [String] = ["/usr/bin/swift", "test"]

        // Determine test filter based on scope
        var testFilter = filter
        if testFilter.isEmpty {
            switch scope {
            case "file":
                if !rawPath.isEmpty {
                    let fileName = (rawPath as NSString).lastPathComponent.replacingOccurrences(of: ".swift", with: "")
                    testFilter = fileName
                }
            case "related":
                if !rawPath.isEmpty {
                    let fileName = (rawPath as NSString).lastPathComponent.replacingOccurrences(of: ".swift", with: "")
                    testFilter = fileName
                } else if !hypothesisId.isEmpty, let hyp = debugHypotheses[hypothesisId] {
                    let fileNames = hyp.relatedFiles.compactMap { ($0 as NSString).lastPathComponent.replacingOccurrences(of: ".swift", with: "") }
                    if let first = fileNames.first { testFilter = first }
                }
            case "failing":
                if let firstFailing = debugFailingTestFilters.first {
                    testFilter = firstFailing
                } else {
                    let ms = Int(Date().timeIntervalSince(startDate) * 1000)
                    return ToolResult(ok: true, payload: [
                        "title": "debug_test_check",
                        "detail": "No previously failing tests to run [failing]",
                        "output": "No previously failing tests recorded in this runtime session.",
                        "scope": scope,
                        "passed": "0",
                        "failed": "0",
                        "exit_code": "0",
                        "overall_status": "skipped",
                        "filter": ""
                    ], durationMs: ms)
                }
            case "all":
                break
            default:
                break
            }
        }

        if !testFilter.isEmpty {
            testArgs += ["--filter", testFilter]
        }

        await debugLogServer.log(
            severity: "info",
            source: "debug_test_check",
            message: "Running tests [scope=\(scope)]\(testFilter.isEmpty ? "" : " filter=\(testFilter)")",
            category: "test"
        )

        let (stdout, stderr, exitCode) = await shellExec(
            args: testArgs,
            cwd: workspace,
            timeout: timeoutMs
        )

        let combined = (stdout + "\n" + stderr).trimmingCharacters(in: .whitespacesAndNewlines)

        // Parse test results
        var passed = 0
        var failed = 0
        var failedTests: [String] = []
        let resultLines = combined.components(separatedBy: "\n")
        for line in resultLines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.contains("passed") && trimmed.contains("Test Case") {
                passed += 1
            } else if trimmed.contains("failed") && trimmed.contains("Test Case") {
                failed += 1
                failedTests.append(trimmed)
            }
        }

        // Check for overall pass/fail from Swift test summary
        let overallPassed = exitCode == 0

        var dedupedFailingFilters: [String] = []
        var seenFailingFilters: Set<String> = []
        for failedLine in failedTests {
            if let parsed = parseSwiftTestFilter(from: failedLine), seenFailingFilters.insert(parsed).inserted {
                dedupedFailingFilters.append(parsed)
            }
        }
        if overallPassed {
            debugFailingTestFilters.removeAll()
        } else if !dedupedFailingFilters.isEmpty {
            debugFailingTestFilters = dedupedFailingFilters
        }

        await debugLogServer.log(
            severity: overallPassed ? "info" : "error",
            source: "debug_test_check",
            message: "Tests \(overallPassed ? "PASSED" : "FAILED"): \(passed) passed, \(failed) failed",
            detail: failedTests.isEmpty ? nil : failedTests.joined(separator: "\n"),
            category: "test"
        )

        var output = "## Test Results [\(scope)]\n\n"
        output += "- Status: \(overallPassed ? "PASSED ✓" : "FAILED ✗")\n"
        output += "- Passed: \(passed)\n"
        output += "- Failed: \(failed)\n"
        if !testFilter.isEmpty { output += "- Filter: \(testFilter)\n" }
        if !failedTests.isEmpty {
            output += "\n### Failed Tests\n" + failedTests.map { "  - \($0)" }.joined(separator: "\n")
        }
        output += "\n\n### Output (truncated)\n```\n\(String(combined.suffix(2000)))\n```"

        let ms = Int(Date().timeIntervalSince(startDate) * 1000)
        return ToolResult(ok: overallPassed, payload: [
            "title": "debug_test_check",
            "detail": "\(overallPassed ? "PASSED" : "FAILED"): \(passed) passed, \(failed) failed [\(scope)]",
            "output": output,
            "scope": scope,
            "passed": "\(passed)",
            "failed": "\(failed)",
            "exit_code": "\(exitCode)",
            "overall_status": overallPassed ? "passed" : "failed",
            "filter": testFilter,
            "error_code": overallPassed ? "" : "test_failed"
        ], durationMs: ms)
    }

    func parseSwiftTestFilter(from line: String) -> String? {
        guard let start = line.range(of: "'"),
              let end = line.range(of: "'", range: start.upperBound..<line.endIndex)
        else {
            return nil
        }
        let qualified = String(line[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !qualified.isEmpty else { return nil }
        if let bracketStart = qualified.lastIndex(of: "["), let bracketEnd = qualified.lastIndex(of: "]"), bracketStart < bracketEnd {
            let inside = qualified[qualified.index(after: bracketStart)..<bracketEnd]
            return String(inside)
        }
        return qualified
    }

    // MARK: - semantic_search: Search code by meaning using index + heuristic ranking

    func executeDebugContext(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let workspace = context.workspaceContext.workspacePath.path
        let workspacePaths = context.workspaceContext.workspacePaths.map(\.path)
        let preferredRoot = context.workspaceContext.activeRootPath
        var sections: [String] = []

        let scopeRaw = call.args["scope"] ?? "full"
        let scopes = Set(scopeRaw.lowercased().split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
        let isFull = scopes.contains("full")
        let includeContent = call.args["include_file_content"]?.lowercased() == "true"
        let maxDepth = max(1, min(8, Int(call.args["max_depth"] ?? "3") ?? 3))

        // 1. Git status + diff + log
        if isFull || scopes.contains("git") {
            let (gitStatus, _, gitExit) = await shellExec(
                args: ["/usr/bin/git", "status", "--short", "--branch"],
                cwd: workspace, timeout: 5_000
            )
            if gitExit == 0 {
                sections.append("## Git Status\n\(gitStatus)")
            }

            let (gitDiff, _, _) = await shellExec(
                args: ["/usr/bin/git", "diff", "--stat", "HEAD"],
                cwd: workspace, timeout: 5_000
            )
            if !gitDiff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sections.append("## Git Diff (stat)\n\(gitDiff)")
            }

            let (gitLog, _, _) = await shellExec(
                args: ["/usr/bin/git", "log", "--oneline", "-5"],
                cwd: workspace, timeout: 5_000
            )
            if !gitLog.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sections.append("## Recent Commits\n\(gitLog)")
            }
        }

        // 2. Build errors
        if isFull || scopes.contains("build") {
            let (buildOut, buildErr, buildExit) = await shellExec(
                args: ["/usr/bin/swift", "build", "--skip-update"],
                cwd: workspace, timeout: 30_000
            )
            let buildOutput = (buildOut + "\n" + buildErr).trimmingCharacters(in: .whitespacesAndNewlines)
            if buildExit != 0 && !buildOutput.isEmpty {
                let truncatedBuild = String(buildOutput.prefix(3000))
                sections.append("## Build Errors (exit \(buildExit))\n```\n\(truncatedBuild)\n```")
            } else {
                sections.append("## Build Status\nClean build (exit 0)")
            }
        }

        // 3. Linter diagnostics
        if isFull || scopes.contains("lints") {
            let lintStartDate = Date()
            let lintCall = ToolCall(
                id: UUID().uuidString, name: "read_lints",
                args: ["severity": "error", "limit": "20"],
                sourceProvider: call.sourceProvider, swarmId: nil, scope: call.scope
            )
            let lintResult = await executeReadLints(call: lintCall, context: context, startDate: lintStartDate)
            if lintResult.ok {
                let errorCount = lintResult.payload["error_count"] ?? "0"
                let warningCount = lintResult.payload["warning_count"] ?? "0"
                let linter = lintResult.payload["linter"] ?? "unknown"
                var lintSection = "## Linter Diagnostics (\(linter))\nErrors: \(errorCount), Warnings: \(warningCount)"
                if let output = lintResult.payload["output"], !output.isEmpty, errorCount != "0" {
                    lintSection += "\n```\n\(String(output.prefix(2000)))\n```"

                    if includeContent {
                        let errorFiles = parseErrorFiles(from: output)
                        for (filePath, lineNum) in errorFiles.prefix(5) {
                            guard let fullPath = resolvePath(
                                filePath,
                                workspacePaths: workspacePaths,
                                preferredRoot: preferredRoot,
                                sandboxMode: context.policy.sandboxMode
                            ) else {
                                continue
                            }
                            let owningRoot = workspacePaths.first(where: { root in
                                let normalizedRoot = URL(fileURLWithPath: root).standardizedFileURL.path
                                let normalizedPath = URL(fileURLWithPath: fullPath).standardizedFileURL.path
                                return normalizedPath == normalizedRoot || normalizedPath.hasPrefix(normalizedRoot + "/")
                            }) ?? workspace
                            let relativePath = fullPath.hasPrefix(owningRoot + "/")
                                ? String(fullPath.dropFirst(owningRoot.count + 1))
                                : fullPath
                            let pathDepth = max(1, relativePath.split(separator: "/").count)
                            guard pathDepth <= maxDepth else { continue }
                            if let fileContent = try? String(contentsOfFile: fullPath, encoding: .utf8) {
                                let allLines = fileContent.components(separatedBy: "\n")
                                let start = max(0, lineNum - 10)
                                let end = min(allLines.count, lineNum + 10)
                                let snippet = allLines[start..<end].enumerated().map { "\(start + $0.offset + 1)| \($0.element)" }.joined(separator: "\n")
                                lintSection += "\n\n### \(filePath):\(lineNum)\n```\n\(snippet)\n```"
                            }
                        }
                    }
                }
                sections.append(lintSection)
            }
        }

        // 4. Environment info
        if isFull || scopes.contains("env") {
            var envLines: [String] = []
            let (swiftVer, _, _) = await shellExec(
                args: ["/usr/bin/swift", "--version"],
                cwd: workspace, timeout: 5_000
            )
            if !swiftVer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                envLines.append("Swift: \(swiftVer.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n").first ?? swiftVer)")
            }

            let (xcodeVer, _, _) = await shellExec(
                args: ["/usr/bin/xcodebuild", "-version"],
                cwd: workspace, timeout: 5_000
            )
            if !xcodeVer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                envLines.append("Xcode: \(xcodeVer.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: ", "))")
            }

            let (sdkPath, _, _) = await shellExec(
                args: ["/usr/bin/xcrun", "--show-sdk-path"],
                cwd: workspace, timeout: 5_000
            )
            if !sdkPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                envLines.append("SDK: \(sdkPath.trimmingCharacters(in: .whitespacesAndNewlines))")
            }

            envLines.append("Platform: \(ProcessInfo.processInfo.operatingSystemVersionString)")
            envLines.append("CPU cores: \(ProcessInfo.processInfo.activeProcessorCount)")

            sections.append("## Environment\n\(envLines.joined(separator: "\n"))")
        }

        // 5. Test listing
        if isFull || scopes.contains("tests") {
            let (testListOut, testListErr, testExit) = await shellExec(
                args: ["/usr/bin/swift", "test", "list"],
                cwd: workspace, timeout: 15_000
            )
            let trimmed = (testListOut + "\n" + testListErr).trimmingCharacters(in: .whitespacesAndNewlines)
            if testExit == 0 && !trimmed.isEmpty {
                let testLines = trimmed.components(separatedBy: "\n")
                sections.append("## Tests (\(testLines.count) test cases)\n\(testLines.prefix(30).joined(separator: "\n"))\(testLines.count > 30 ? "\n... +\(testLines.count - 30) more" : "")")
            } else if !trimmed.isEmpty {
                sections.append("## Tests\n```\n\(String(trimmed.prefix(1500)))\n```")
            }
        }

        // 6. Recent crash reports
        if isFull || scopes.contains("crashes") {
            let crashDir = NSHomeDirectory() + "/Library/Logs/DiagnosticReports"
            let fm = FileManager.default
            if fm.fileExists(atPath: crashDir) {
                let (crashFiles, _, _) = await shellExec(
                    args: ["/bin/ls", "-t", crashDir],
                    cwd: workspace, timeout: 3_000
                )
                let files = crashFiles.components(separatedBy: "\n").filter { !$0.isEmpty }
                let recentCrashes = files.prefix(5)
                if !recentCrashes.isEmpty {
                    var crashSection = "## Recent Crash Reports (\(files.count) total, showing \(recentCrashes.count))\n"
                    for crashFile in recentCrashes {
                        crashSection += "- \(crashFile)\n"
                    }
                    sections.append(crashSection)
                }
            }
        }

        // 7. Dependencies (Package.resolved)
        if isFull || scopes.contains("build") {
            let resolvedPath = workspace + "/Package.resolved"
            if FileManager.default.fileExists(atPath: resolvedPath) {
                if let resolvedContent = try? String(contentsOfFile: resolvedPath, encoding: .utf8) {
                    let truncated = String(resolvedContent.prefix(2000))
                    sections.append("## Dependencies (Package.resolved)\n```json\n\(truncated)\n```")
                }
            }
        }

        // 8. Open files
        let openFiles = context.workspaceContext.openFiles
        if !openFiles.isEmpty {
            var fileSection = "## Open Files (\(openFiles.count))\n"
            for file in openFiles {
                let lineCount = file.content.components(separatedBy: "\n").count
                fileSection += "- \(file.path) (\(lineCount) lines)\n"
            }
            sections.append(fileSection)
        }

        // 9. Active file and selection
        if let activeFile = context.workspaceContext.activeFilePath {
            sections.append("## Active File\n\(activeFile)")
        }
        if let selection = context.workspaceContext.activeSelection, !selection.isEmpty {
            let preview = selection.count > 500 ? String(selection.prefix(500)) + "..." : selection
            sections.append("## Active Selection\n```\n\(preview)\n```")
        }

        // 10. Debug log summary
        let debugSnapshot = await debugLogServer.query(limit: 5)
        if debugSnapshot.totalCount > 0 {
            let summary = await debugLogServer.sessionSummary()
            if !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sections.append("## Debug Log Summary\n\(summary)")
            }
        }

        let ms = Int(Date().timeIntervalSince(startDate) * 1000)
        let fullContext = sections.joined(separator: "\n\n")

        return ToolResult(ok: true, payload: [
            "title": "debug_context",
            "detail": "Debug context gathered: \(sections.count) sections [\(scopes.joined(separator: ","))]",
            "output": truncate(fullContext, maxBytes: context.policy.maxBashOutputBytes),
            "sections": "\(sections.count)",
            "scopes": scopeRaw
        ], durationMs: ms)
    }

    func parseErrorFiles(from lintOutput: String) -> [(String, Int)] {
        var result: [(String, Int)] = []
        let lines = lintOutput.components(separatedBy: "\n")
        for line in lines {
            let parts = line.split(separator: ":", maxSplits: 3)
            if parts.count >= 3,
               let lineNum = Int(parts[1].trimmingCharacters(in: .whitespaces)) {
                let filePath = String(parts[0])
                if !result.contains(where: { $0.0 == filePath && $0.1 == lineNum }) {
                    result.append((filePath, lineNum))
                }
            }
        }
        return result
    }

    // MARK: - apply_diff
}
