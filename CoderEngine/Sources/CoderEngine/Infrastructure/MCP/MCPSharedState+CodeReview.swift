import Foundation

// MARK: - Code Review Shared State

extension MCPSharedState {

    public static var codeReviewFilePath: URL {
        sharedDirectory.appendingPathComponent("code_review.json")
    }

    /// Write the current code review snapshot to disk (called by IDE on state change).
    public static func writeCodeReviewSnapshot(_ snapshot: CodeReviewSessionSnapshot) {
        ensureDirectory()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshot) else {
            print("[MCPSharedState] ⚠️ Failed to encode code review snapshot")
            return
        }
        do {
            try data.write(to: codeReviewFilePath, options: .atomic)
        } catch {
            print("[MCPSharedState] ⚠️ Failed to write code review file: \(error.localizedDescription)")
        }
    }

    /// Read the current code review snapshot (called by MCP server for review_status/review_findings).
    public static func readCodeReviewSnapshot() -> CodeReviewSessionSnapshot? {
        guard let data = try? Data(contentsOf: codeReviewFilePath) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CodeReviewSessionSnapshot.self, from: data)
    }

    /// Read findings as serialized payload for MCP response.
    public static func readCodeReviewFindings(
        severity: String? = nil,
        status: String? = nil,
        file: String? = nil,
        limit: Int = 50
    ) -> [[String: String]] {
        guard let snapshot = readCodeReviewSnapshot() else { return [] }
        var findings = snapshot.findings

        if let severity = severity, !severity.isEmpty {
            findings = findings.filter { $0.severity.rawValue == severity }
        }
        if let status = status, !status.isEmpty {
            findings = findings.filter { $0.status.rawValue == status }
        }
        if let file = file, !file.isEmpty {
            findings = findings.filter { $0.filePath.contains(file) }
        }

        return Array(findings.prefix(limit)).map { $0.toPayload() }
    }

    /// Read status summary for MCP response.
    public static func readCodeReviewStatus() -> [String: String] {
        guard let snapshot = readCodeReviewSnapshot() else {
            return ["phase": "idle", "status": "No active review session"]
        }
        var payload: [String: String] = [
            "phase": snapshot.phase.rawValue,
            "findings_total": String(snapshot.findings.count),
            "findings_open": String(snapshot.openFindings.count),
            "current_round": String(snapshot.currentRound),
            "active_workers": String(snapshot.activeWorkerCount),
        ]
        if let scope = snapshot.scope {
            payload["scope"] = scope.type.rawValue
            payload["scope_files"] = String(scope.files.count)
        }
        if let error = snapshot.lastError { payload["error"] = error }
        payload["summary"] = snapshot.statusSummary
        return payload
    }
}
