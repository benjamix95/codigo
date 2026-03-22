import Foundation

public extension DebugLogServer {
    // MARK: - Session Management

    func startSession() -> String {
        ensureLoadedFromDiskIfNeeded()
        let sessionId = UUID().uuidString
        activeSessionId = sessionId
        let entry = LogEntry(
            severity: "info",
            source: "debug_server",
            message: "Debug session started",
            category: "system",
            sessionId: sessionId
        )
        append(entry)
        return sessionId
    }

    func endSession() {
        ensureLoadedFromDiskIfNeeded()
        if let sid = activeSessionId {
            let entry = LogEntry(
                severity: "info",
                source: "debug_server",
                message: "Debug session ended",
                category: "system",
                sessionId: sid
            )
            append(entry)
        }
        activeSessionId = nil
    }

    // MARK: - Write

    func log(
        severity: String,
        source: String,
        message: String,
        detail: String? = nil,
        category: String? = nil,
        runId: String? = nil,
        hypothesisId: String? = nil,
        data: [String: String]? = nil
    ) {
        ensureLoadedFromDiskIfNeeded()
        let entry = LogEntry(
            severity: severity,
            source: source,
            message: message,
            detail: detail,
            category: category,
            sessionId: activeSessionId,
            runId: runId,
            hypothesisId: hypothesisId,
            data: data
        )
        append(entry)
    }

    func logRuntime(
        source: String,
        message: String,
        severity: String = "info",
        detail: String? = nil,
        category: String = "instrumentation",
        data: [String: String] = [:],
        runId: String? = nil,
        hypothesisId: String? = nil
    ) {
        ensureLoadedFromDiskIfNeeded()
        let entry = LogEntry(
            severity: severity,
            source: source,
            message: message,
            detail: detail,
            category: category,
            sessionId: activeSessionId,
            runId: runId,
            hypothesisId: hypothesisId,
            data: data.isEmpty ? nil : data
        )
        append(entry)
    }

    func queryRuntime(
        runId: String? = nil,
        hypothesisId: String? = nil,
        limit: Int = 100
    ) -> [LogEntry] {
        ensureLoadedFromDiskIfNeeded()
        var filtered = entries.filter { $0.category == "instrumentation" || $0.category == "runtime" }
        if let rid = runId {
            filtered = filtered.filter { $0.runId == rid }
        }
        if let hid = hypothesisId,
           !hid.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            filtered = QueryResult(
                entries: filtered,
                totalCount: filtered.count,
                errorCount: filtered.filter { $0.severity == "error" }.count,
                warningCount: filtered.filter { $0.severity == "warning" }.count
            ).filteredByHypothesisId(hid).entries
        }
        return Array(filtered.suffix(limit))
    }

    func logBuildOutput(_ output: String, source: String = "build") {
        ensureLoadedFromDiskIfNeeded()
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let severity: String
            if trimmed.contains("error:") || trimmed.contains("Error:") {
                severity = "error"
            } else if trimmed.contains("warning:") || trimmed.contains("Warning:") {
                severity = "warning"
            } else if trimmed.contains("note:") {
                severity = "info"
            } else {
                severity = "verbose"
            }

            append(LogEntry(
                severity: severity,
                source: source,
                message: trimmed,
                category: "compiler",
                sessionId: activeSessionId
            ))
        }
    }

    func logTestOutput(_ output: String, source: String = "test") {
        ensureLoadedFromDiskIfNeeded()
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let severity: String
            if trimmed.contains("FAIL") || trimmed.contains("failed") {
                severity = "error"
            } else if trimmed.contains("PASS") || trimmed.contains("passed") {
                severity = "info"
            } else {
                severity = "verbose"
            }

            append(LogEntry(
                severity: severity,
                source: source,
                message: trimmed,
                category: "test",
                sessionId: activeSessionId
            ))
        }
    }

    func logRuntimeError(_ error: String, source: String, stackTrace: String? = nil) {
        ensureLoadedFromDiskIfNeeded()
        append(LogEntry(
            severity: "error",
            source: source,
            message: error,
            detail: stackTrace,
            category: "runtime",
            sessionId: activeSessionId
        ))
    }

    // MARK: - Hypothesis Persistence

    /// Persist hypothesis state as a special log entry so it survives runtime restarts.
    func persistHypothesis(
        id: String,
        title: String,
        status: String,
        confidence: Int,
        description: String,
        rootCauseType: String,
        relatedFiles: [String],
        evidence: [String]
    ) {
        ensureLoadedFromDiskIfNeeded()
        var data: [String: String] = [
            "hypothesis_id": id,
            "title": title,
            "status": status,
            "confidence": "\(confidence)",
            "description": description,
        ]
        if !rootCauseType.isEmpty { data["root_cause_type"] = rootCauseType }
        if !relatedFiles.isEmpty { data["related_files"] = relatedFiles.joined(separator: ",") }
        if !evidence.isEmpty { data["evidence"] = evidence.joined(separator: "|||") }

        append(LogEntry(
            severity: "info",
            source: "hypothesis_persist",
            message: "[\(status)] \(title)",
            detail: description,
            category: "hypothesis_state",
            sessionId: activeSessionId,
            hypothesisId: id,
            data: data
        ))
    }

    /// Recover persisted hypotheses from log entries after restart.
    func recoverHypotheses() -> [(id: String, title: String, status: String, confidence: Int, description: String, rootCauseType: String, relatedFiles: [String], evidence: [String])] {
        ensureLoadedFromDiskIfNeeded()
        // Find latest hypothesis_state entry per hypothesis_id
        var latestByHypId: [String: LogEntry] = [:]
        for entry in entries where entry.category == "hypothesis_state" {
            guard let data = entry.data, let hid = data["hypothesis_id"] else { continue }
            latestByHypId[hid] = entry
        }

        return latestByHypId.values.compactMap { entry in
            guard let data = entry.data,
                  let hid = data["hypothesis_id"],
                  let title = data["title"],
                  let status = data["status"] else { return nil }
            let confidence = Int(data["confidence"] ?? "50") ?? 50
            let description = data["description"] ?? ""
            let rootCauseType = data["root_cause_type"] ?? ""
            let relatedFiles = (data["related_files"] ?? "").split(separator: ",").map(String.init).filter { !$0.isEmpty }
            let evidence = (data["evidence"] ?? "").components(separatedBy: "|||").filter { !$0.isEmpty }
            return (id: hid, title: title, status: status, confidence: confidence, description: description, rootCauseType: rootCauseType, relatedFiles: relatedFiles, evidence: evidence)
        }
    }

}
