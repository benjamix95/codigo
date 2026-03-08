import Foundation

public struct MCPSharedCodeReviewSessionRecord: Codable, Sendable {
    public let sessionId: String
    public let conversationId: String?
    public let phase: String
    public let stage: String
    public let findingsCount: Int
    public let openFindingsCount: Int
    public let currentRound: Int
    public let activeWorkerCount: Int
    public let scopeType: String?
    public let scopeRef: String?
    public let startedAt: Date?
    public let updatedAt: Date
    public let isActive: Bool
}

public struct MCPSharedCodeReviewIndex: Codable, Sendable {
    public var latestSessionId: String?
    public var latestSessionIdByConversation: [String: String]
    public var sessions: [MCPSharedCodeReviewSessionRecord]

    public init(
        latestSessionId: String? = nil,
        latestSessionIdByConversation: [String: String] = [:],
        sessions: [MCPSharedCodeReviewSessionRecord] = []
    ) {
        self.latestSessionId = latestSessionId
        self.latestSessionIdByConversation = latestSessionIdByConversation
        self.sessions = sessions
    }
}

extension MCPSharedState {
    private static let allowedCodeReviewSessionIdCharacters = CharacterSet.alphanumerics
        .union(CharacterSet(charactersIn: "-_"))
    private static let redactedFindingLabelPrefix = "redacted"

    public static func sanitizedCodeReviewSessionId(_ sessionId: String?) -> String? {
        guard let sessionId else { return nil }
        let normalized = sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.count <= 128 else { return nil }
        guard normalized.rangeOfCharacter(from: allowedCodeReviewSessionIdCharacters.inverted) == nil else {
            return nil
        }
        guard let firstScalar = normalized.unicodeScalars.first,
              CharacterSet.alphanumerics.contains(firstScalar) else {
            return nil
        }
        return normalized
    }

    public static var codeReviewDirectoryPath: URL {
        sharedDirectory.appendingPathComponent("code-review")
    }

    public static var codeReviewIndexFilePath: URL {
        codeReviewDirectoryPath.appendingPathComponent("index.json")
    }

    public static var codeReviewSessionsDirectoryPath: URL {
        codeReviewDirectoryPath.appendingPathComponent("sessions")
    }

    public static func codeReviewSessionFilePath(sessionId: String) -> URL {
        codeReviewSessionsDirectoryPath.appendingPathComponent("\(sessionId).json")
    }

    private static func validatedCodeReviewSessionFilePath(sessionId: String) -> URL? {
        guard let safeSessionId = sanitizedCodeReviewSessionId(sessionId) else { return nil }
        return codeReviewSessionFilePath(sessionId: safeSessionId)
    }

    public static func writeCodeReviewSnapshot(_ snapshot: CodeReviewSessionSnapshot) {
        withCodeReviewFileLock {
            _writeCodeReviewSnapshotUnsafe(snapshot)
        }
    }

    public static func readCodeReviewIndex() -> MCPSharedCodeReviewIndex {
        withCodeReviewFileLock {
            rebuiltCodeReviewIndexUnsafe()
        }
    }

    public static func readCodeReviewSnapshot(sessionId: String) -> CodeReviewSessionSnapshot? {
        withCodeReviewFileLock {
            _readCodeReviewSnapshotUnsafe(sessionId: sessionId)
        }
    }

    public static func readCodeReviewSnapshots(
        conversationId: UUID? = nil
    ) -> [CodeReviewSessionSnapshot] {
        withCodeReviewFileLock {
            let normalizedConversationId = conversationId?.uuidString.lowercased()
            return allCodeReviewSnapshotsUnsafe()
                .filter { snapshot in
                    guard let normalizedConversationId else { return true }
                    return snapshot.conversationId?.uuidString.lowercased() == normalizedConversationId
                }
                .sorted(by: sortCodeReviewSnapshots)
        }
    }

    public static func latestCodeReviewSessionId(
        conversationId: UUID? = nil
    ) -> String? {
        readCodeReviewSnapshots(conversationId: conversationId).first?.sessionId
    }

    public static func readCodeReviewFindings(
        sessionId: String,
        kind: String? = nil,
        severity: String? = nil,
        status: String? = nil,
        origin: String? = nil,
        category: String? = nil,
        file: String? = nil,
        limit: Int = 50,
        includeSensitiveDetails: Bool = false
    ) -> [[String: String]] {
        guard let snapshot = readCodeReviewSnapshot(sessionId: sessionId) else {
            return []
        }
        let normalizedKind = (kind ?? "verified")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if normalizedKind == "candidate" || normalizedKind == "candidates" {
            var candidates = snapshot.candidates
            if let severity, !severity.isEmpty {
                candidates = candidates.filter { $0.severity.rawValue == severity }
            }
            if let origin, !origin.isEmpty {
                candidates = candidates.filter { $0.origin.rawValue == origin }
            }
            if let category, !category.isEmpty {
                candidates = candidates.filter { $0.category.rawValue == FindingCategory.fromStoredValue(category).rawValue }
            }
            if let file, !file.isEmpty {
                candidates = candidates.filter { $0.filePath.contains(file) }
            }
            return Array(candidates.prefix(limit)).map { candidate in
                var payload: [String: String] = [
                    "id": candidate.id,
                    "kind": "candidate",
                    "severity": candidate.severity.rawValue,
                    "category": candidate.category.rawValue,
                    "origin": candidate.origin.rawValue,
                    "status": candidate.verificationStatus.rawValue,
                ]
                if let confidence = candidate.confidence {
                    payload["confidence"] = String(format: "%.2f", confidence)
                }
                if includeSensitiveDetails {
                    payload["file_path"] = candidate.filePath
                    payload["message"] = candidate.message
                    payload["evidence"] = candidate.evidence
                    if let ln = candidate.lineNumber {
                        payload["line_number"] = String(ln)
                    }
                } else {
                    payload["file_label"] = redactedFindingReference(for: CodeReviewFinding.fromCandidate(candidate))
                    payload["message_summary"] = redactedFindingSummary(for: CodeReviewFinding.fromCandidate(candidate))
                }
                return payload
            }
        }

        var findings = snapshot.findings
        if let severity, !severity.isEmpty {
            findings = findings.filter { $0.severity.rawValue == severity }
        }
        if let status, !status.isEmpty {
            findings = findings.filter { $0.status.rawValue == status }
        }
        if let origin, !origin.isEmpty {
            findings = findings.filter { $0.origin.rawValue == origin }
        }
        if let category, !category.isEmpty {
            findings = findings.filter { $0.category.rawValue == FindingCategory.fromStoredValue(category).rawValue }
        }
        if let file, !file.isEmpty {
            findings = findings.filter { $0.filePath.contains(file) }
        }

        return Array(findings.prefix(limit)).map { finding in
            var payload: [String: String] = [
                "id": finding.id,
                "kind": "verified",
                "severity": finding.severity.rawValue,
                "category": finding.category.rawValue,
                "origin": finding.origin.rawValue,
                "status": finding.status.rawValue,
                "blocking": finding.blocking ? "true" : "false",
            ]
            if let confidence = finding.confidence {
                payload["confidence"] = String(format: "%.2f", confidence)
            }
            if let sourceTool = finding.sourceTool {
                payload["source_tool"] = sourceTool
            }
            if includeSensitiveDetails {
                payload["file_path"] = finding.filePath
                payload["message"] = finding.message
                if let ln = finding.lineNumber {
                    payload["line_number"] = String(ln)
                }
                if let eln = finding.endLineNumber {
                    payload["end_line_number"] = String(eln)
                }
            } else {
                payload["file_label"] = redactedFindingReference(for: finding)
                payload["message_summary"] = redactedFindingSummary(for: finding)
                if let ln = finding.lineNumber {
                    payload["line_number"] = String(ln)
                }
            }
            return payload
        }
    }

    public static func readCodeReviewStatus(sessionId: String) -> [String: String]? {
        guard let snapshot = readCodeReviewSnapshot(sessionId: sessionId) else {
            return nil
        }
        var payload: [String: String] = [
            "session_id": snapshot.sessionId,
            "phase": snapshot.phase.rawValue,
            "stage": snapshot.stage.rawValue,
            "findings_total": String(snapshot.findings.count),
            "candidates_total": String(snapshot.candidates.count),
            "patches_total": String(snapshot.patches.count),
            "findings_open": String(snapshot.openFindings.count),
            "findings_blocking_open": String(snapshot.blockingOpenFindings.count),
            "current_round": String(snapshot.currentRound),
            "active_workers": String(snapshot.activeWorkerCount),
            "summary": snapshot.statusSummary,
        ]
        payload["false_positive_candidates"] = String(snapshot.falsePositiveCandidatesCount)
        payload["patches_ready"] = String(snapshot.outcome.patchesReady)
        payload["patches_applied"] = String(snapshot.outcome.patchesApplied)
        payload["prs_opened"] = String(snapshot.outcome.prsOpened)
        payload["merged_patches"] = String(snapshot.outcome.mergedPatches)
        payload["manual_action_required"] = snapshot.outcome.manualActionRequired ? "true" : "false"
        payload["audit_coverage_percent"] = String(format: "%.0f", snapshot.auditCoveragePercent)
        if !snapshot.audit.toolCoverage.isEmpty {
            payload["findings_by_origin"] = snapshot.findingsByOrigin
                .map { "\($0.key.rawValue)=\($0.value.count)" }
                .sorted()
                .joined(separator: ",")
            payload["audit_tools"] = snapshot.audit.toolCoverage
                .map { "\($0.key)=\($0.value ? "covered" : "unavailable")" }
                .sorted()
                .joined(separator: ",")
            payload["audit_durations_ms"] = snapshot.audit.toolDurationsMs
                .map { "\($0.key)=\($0.value)" }
                .sorted()
                .joined(separator: ",")
        }
        if let conversationId = snapshot.conversationId {
            payload["conversation_id"] = conversationId.uuidString.lowercased()
        }
        if let scope = snapshot.scope {
            payload["scope"] = scope.type.rawValue
            payload["scope_files"] = String(scope.files.count)
            if let ref = scope.ref {
                payload["scope_ref"] = ref
            }
        }
        if let workspacePath = snapshot.workspacePath {
            payload["workspace_path"] = workspacePath
        }
        if let jobId = snapshot.currentJobId {
            payload["job_id"] = jobId
        }
        if let error = snapshot.lastError {
            payload["error"] = error
        }
        if let testStatus = snapshot.lastTestStatus {
            payload["last_test_status"] = testStatus.rawValue
        }
        return payload
    }

    public static func deleteCodeReviewSession(sessionId: String) {
        withCodeReviewFileLock {
            guard let snapshotFilePath = validatedCodeReviewSessionFilePath(sessionId: sessionId) else {
                return
            }
            try? FileManager.default.removeItem(at: snapshotFilePath)
            _writeCodeReviewIndexUnsafe(rebuiltCodeReviewIndexUnsafe())
        }
    }

    private static func _writeCodeReviewSnapshotUnsafe(_ snapshot: CodeReviewSessionSnapshot) {
        ensureCodeReviewDirectories()
        guard let snapshotFilePath = validatedCodeReviewSessionFilePath(sessionId: snapshot.sessionId) else {
            print("[MCPSharedState] ⚠️ Ignoring code review snapshot with invalid session id")
            return
        }
        if let currentSnapshot = _readCodeReviewSnapshotUnsafe(sessionId: snapshot.sessionId),
           shouldSkipCodeReviewSnapshotWrite(current: currentSnapshot, incoming: snapshot) {
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshot) else {
            print("[MCPSharedState] ⚠️ Failed to encode code review snapshot")
            return
        }
        do {
            try data.write(
                to: snapshotFilePath,
                options: .atomic
            )
            _writeCodeReviewIndexUnsafe(rebuiltCodeReviewIndexUnsafe())
        } catch {
            print("[MCPSharedState] ⚠️ Failed to write code review snapshot: \(error.localizedDescription)")
        }
    }

    private static func _writeCodeReviewIndexUnsafe(_ index: MCPSharedCodeReviewIndex) {
        ensureCodeReviewDirectories()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(index) else {
            print("[MCPSharedState] ⚠️ Failed to encode code review index")
            return
        }
        do {
            try data.write(to: codeReviewIndexFilePath, options: .atomic)
        } catch {
            print("[MCPSharedState] ⚠️ Failed to write code review index: \(error.localizedDescription)")
        }
    }

    private static func _readCodeReviewSnapshotUnsafe(
        sessionId: String
    ) -> CodeReviewSessionSnapshot? {
        guard let snapshotFilePath = validatedCodeReviewSessionFilePath(sessionId: sessionId),
              let data = try? Data(contentsOf: snapshotFilePath) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CodeReviewSessionSnapshot.self, from: data)
    }

    static func allCodeReviewSnapshotsUnsafe() -> [CodeReviewSessionSnapshot] {
        ensureCodeReviewDirectories()
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: codeReviewSessionsDirectoryPath,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }
        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                let sessionId = url.deletingPathExtension().lastPathComponent
                return _readCodeReviewSnapshotUnsafe(sessionId: sessionId)
            }
    }

    private static func ensureCodeReviewDirectories() {
        ensureDirectory()
        let directories = [codeReviewDirectoryPath, codeReviewSessionsDirectoryPath]
        for directory in directories where !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private static func redactedFindingReference(for finding: CodeReviewFinding) -> String {
        let ext = (finding.filePath as NSString).pathExtension.lowercased()
        let fileClass = ext.isEmpty ? "file" : "\(ext)-file"
        return "\(redactedFindingLabelPrefix)-\(fileClass)-\(stableRedactionSuffix(for: finding.filePath))"
    }

    private static func redactedFindingSummary(for finding: CodeReviewFinding) -> String {
        let category = finding.category.rawValue.replacingOccurrences(of: "_", with: " ")
        return "Redacted \(finding.severity.rawValue) \(category) finding"
    }

    private static func stableRedactionSuffix(for value: String) -> String {
        var hash: UInt32 = 2_166_136_261
        for byte in value.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return String(format: "%08x", hash)
    }
}
