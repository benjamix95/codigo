import Foundation

extension UnifiedToolRuntime {
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
        guard let jsonData = batchJSON.data(using: .utf8) else {
            return ToolResult(ok: false, payload: ["detail": "batch must be valid UTF-8 text"], durationMs: 0)
        }
        let entries: [[String: Any]]
        if let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] {
            entries = parsed
        } else {
            // Fallback: try to log the raw text as a single entry
            await debugLogServer.log(
                severity: "warning",
                source: "debug_log_batch",
                message: "Batch JSON parse failed — logged raw text as single entry",
                detail: batchJSON,
                category: "debug"
            )
            let ms = Int(Date().timeIntervalSince(startDate) * 1000)
            return ToolResult(ok: true, payload: [
                "title": "debug_log (batch fallback)",
                "detail": "JSON parse failed — raw text logged as single entry",
                "output": "Batch parse failed. Logged raw text as fallback.",
                "logged_count": "1",
                "total_count": "1"
            ], durationMs: ms)
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

}
