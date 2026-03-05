import Foundation

extension EventNormalizer {
    static let todoClearMarkerTitle = "__CODERIDE_CLEAR_TODOS__"

    static func parseTodoWrite(payload: [String: String]) -> TodoWritePayload? {
        let title = (
            payload["title"]
            ?? payload["task"]
            ?? payload["name"]
            ?? payload["item"]
            ?? payload["detail"]
            ?? payload["summary"]
        )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !title.isEmpty else { return nil }

        let id = payload["id"].flatMap(UUID.init(uuidString:))
        let status = normalizedTodoStatus(payload["status"])
        let priority = normalizedTodoPriority(payload["priority"])
        let notes = payload["notes"]
        let activeForm = (payload["activeForm"] ?? payload["active_form"])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let files = normalizeFileList(from: payload)

        return TodoWritePayload(
            id: id,
            title: title,
            status: status,
            priority: priority,
            notes: notes,
            activeForm: activeForm,
            files: files
        )
    }

    static func normalizeFileList(from payload: [String: String]) -> [String] {
        let keys = ["files", "linkedFiles", "linked_files"]
        var merged: [String] = []
        for key in keys {
            guard let rawValue = payload[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rawValue.isEmpty else {
                continue
            }

            // Accept both JSON array strings and plain CSV values.
            if rawValue.hasPrefix("["),
               let data = rawValue.data(using: .utf8),
               let decoded = try? JSONSerialization.jsonObject(with: data) as? [String] {
                merged.append(contentsOf: decoded)
                continue
            }

            merged.append(contentsOf: rawValue.split(separator: ",").map(String.init))
        }

        var seen = Set<String>()
        return merged
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0).inserted }
    }

    static func normalizedTodoStatus(_ raw: String?) -> TodoStatus? {
        guard let raw else { return nil }
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        if let direct = TodoStatus(rawValue: normalized) { return direct }

        switch normalized {
        case "completed", "complete", "finished":
            return .done
        case "running", "active", "doing", "started":
            return .inProgress
        case "todo", "open", "queued", "waiting":
            return .pending
        case "failed", "error", "stuck":
            return .blocked
        default:
            return nil
        }
    }

    static func normalizedTodoPriority(_ raw: String?) -> TodoPriority? {
        guard let raw else { return nil }
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return TodoPriority(rawValue: normalized)
    }

    static func parseDebugLogPayload(payload: [String: String]) -> DebugLogToolPayload? {
        let severity = normalizeDebugSeverity(payload["severity"])
        let source = payload["source"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "agent"
        let message = payload["message"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? payload["detail"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? ""
        guard !message.isEmpty else { return nil }

        let data = parseDebugData(payload["data"])
        return DebugLogToolPayload(
            severity: severity,
            source: source,
            message: message,
            detail: payload["log_detail"]?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? payload["detail"]?.trimmingCharacters(in: .whitespacesAndNewlines),
            category: payload["category"]?.trimmingCharacters(in: .whitespacesAndNewlines),
            data: data,
            runId: payload["run_id"]?.trimmingCharacters(in: .whitespacesAndNewlines),
            hypothesisId: payload["hypothesis_id"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    static func parseDebugHypothesizePayload(payload: [String: String]) -> DebugHypothesizeToolPayload? {
        let action = (payload["action"] ?? "propose")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let hypothesisIdRaw = payload["hypothesis_id"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return DebugHypothesizeToolPayload(
            action: action,
            hypothesisId: hypothesisIdRaw.flatMap(UUID.init(uuidString:)),
            hypothesisIdRaw: hypothesisIdRaw,
            title: payload["hypothesis_title"]?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? payload["title"]?.trimmingCharacters(in: .whitespacesAndNewlines),
            description: payload["description"]?.trimmingCharacters(in: .whitespacesAndNewlines),
            status: normalizeHypothesisStatus(payload["hypothesis_status"] ?? payload["status"]),
            evidence: payload["evidence"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    static func parseDebugMarkPayload(payload: [String: String]) -> DebugMarkToolPayload? {
        let originalContent = payload["original_content"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let markerInfo = payload["marker_info"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !markerInfo.isEmpty {
            let parts = markerInfo.split(separator: "|", maxSplits: 3).map(String.init)
            if parts.count >= 2, let lineNumber = Int(parts[1]) {
                return DebugMarkToolPayload(
                    filePath: parts[0],
                    lineNumber: lineNumber,
                    comment: parts.count > 2 ? parts[2] : "debug marker",
                    originalContent: originalContent
                )
            }
        }

        let filePath = payload["path"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let line = Int(payload["line"] ?? "")
        guard !filePath.isEmpty, let line else { return nil }
        let comment = payload["comment"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? "debug marker"

        return DebugMarkToolPayload(
            filePath: filePath,
            lineNumber: line,
            comment: comment,
            originalContent: originalContent
        )
    }

    static func parseDebugCleanPayload(payload: [String: String]) -> DebugCleanToolPayload? {
        let status = payload["status"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedCount = Int(payload["cleaned_markers"] ?? "") ?? 0
        let filesCount = Int(payload["cleaned_files"] ?? "") ?? 0

        let dryRunRaw = (payload["dry_run"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let dryRun = ["true", "1", "yes"].contains(dryRunRaw)

        if cleanedCount == 0,
           filesCount == 0,
           (payload["detail"] ?? "").isEmpty,
           (status ?? "").isEmpty,
           !dryRun {
            return nil
        }

        return DebugCleanToolPayload(
            cleanedCount: cleanedCount,
            filesCount: filesCount,
            detail: payload["detail"],
            status: status,
            dryRun: dryRun
        )
    }

    static func parseDebugInstrumentPayload(payload: [String: String]) -> DebugInstrumentToolPayload? {
        let filePath = payload["path"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let lineNumber = Int(payload["line"] ?? "")
        guard !filePath.isEmpty, let lineNumber else { return nil }

        return DebugInstrumentToolPayload(
            filePath: filePath,
            lineNumber: lineNumber,
            type: payload["type"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "log",
            expression: payload["expression"]?.trimmingCharacters(in: .whitespacesAndNewlines),
            hypothesisId: payload["hypothesis_id"]?.trimmingCharacters(in: .whitespacesAndNewlines),
            label: payload["label"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    static func parseDebugSessionPayload(payload: [String: String]) -> DebugSessionToolPayload? {
        let action = payload["action"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if action.isEmpty, payload["session_id"] == nil, payload["detail"] == nil {
            return nil
        }
        return DebugSessionToolPayload(
            action: action,
            sessionId: payload["session_id"]?.trimmingCharacters(in: .whitespacesAndNewlines),
            detail: payload["detail"],
            status: payload["status"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    static func parseDebugQueryPayload(payload: [String: String]) -> DebugQueryToolPayload? {
        let format = payload["format"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "summary"
        if payload["detail"] == nil, payload["output"] == nil, payload["status"] == nil {
            return nil
        }
        return DebugQueryToolPayload(
            format: format,
            output: payload["output"],
            detail: payload["detail"],
            status: payload["status"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    static func parseDebugData(_ raw: String?) -> [String: String] {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [:] }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("{"),
           let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            var out: [String: String] = [:]
            for (key, value) in json {
                out[key] = "\(value)"
            }
            return out
        }

        let pairs = raw.split(separator: ",")
        var out: [String: String] = [:]
        for pair in pairs {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2 {
                out[kv[0].trimmingCharacters(in: .whitespacesAndNewlines)] = kv[1]
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return out
    }

    static func normalizeDebugSeverity(_ raw: String?) -> DebugEntrySeverity {
        switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "error":
            return .error
        case "warning":
            return .warning
        case "verbose":
            return .verbose
        case "trace":
            return .trace
        default:
            return .info
        }
    }

    static func normalizeHypothesisStatus(_ raw: String?) -> DebugHypothesis.HypothesisStatus? {
        switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "proposed":
            return .proposed
        case "investigating":
            return .investigating
        case "confirmed":
            return .confirmed
        case "rejected":
            return .rejected
        default:
            return nil
        }
    }

}
