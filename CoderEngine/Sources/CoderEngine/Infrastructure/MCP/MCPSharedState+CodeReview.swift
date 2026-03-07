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

    public static func sanitizedCodeReviewSessionId(_ sessionId: String?) -> String? {
        guard let sessionId else { return nil }
        let normalized = sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, normalized.count <= 128 else { return nil }
        guard normalized.rangeOfCharacter(from: allowedCodeReviewSessionIdCharacters.inverted) == nil else {
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
        severity: String? = nil,
        status: String? = nil,
        file: String? = nil,
        limit: Int = 50,
        includeSensitiveDetails: Bool = false
    ) -> [[String: String]] {
        guard let snapshot = readCodeReviewSnapshot(sessionId: sessionId) else {
            return []
        }
        var findings = snapshot.findings
        if let severity, !severity.isEmpty {
            findings = findings.filter { $0.severity.rawValue == severity }
        }
        if let status, !status.isEmpty {
            findings = findings.filter { $0.status.rawValue == status }
        }
        if let file, !file.isEmpty {
            findings = findings.filter { $0.filePath.contains(file) }
        }

        return Array(findings.prefix(limit)).map { finding in
            var payload: [String: String] = [
                "id": finding.id,
                "severity": finding.severity.rawValue,
                "category": finding.category.rawValue,
                "status": finding.status.rawValue,
            ]
            if includeSensitiveDetails {
                payload["file_path"] = finding.filePath
                payload["message"] = finding.message
                if let ln = finding.lineNumber {
                    payload["line_number"] = String(ln)
                }
                if let eln = finding.endLineNumber {
                    payload["end_line_number"] = String(eln)
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
            "findings_open": String(snapshot.openFindings.count),
            "current_round": String(snapshot.currentRound),
            "active_workers": String(snapshot.activeWorkerCount),
            "summary": snapshot.statusSummary,
        ]
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

    private static func _writeCodeReviewSnapshotUnsafe(_ snapshot: CodeReviewSessionSnapshot) {
        ensureCodeReviewDirectories()
        guard let snapshotFilePath = validatedCodeReviewSessionFilePath(sessionId: snapshot.sessionId) else {
            print("[MCPSharedState] ⚠️ Ignoring code review snapshot with invalid session id")
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

    private static func allCodeReviewSnapshotsUnsafe() -> [CodeReviewSessionSnapshot] {
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

    private static func rebuiltCodeReviewIndexUnsafe() -> MCPSharedCodeReviewIndex {
        let snapshots = allCodeReviewSnapshotsUnsafe().sorted(by: sortCodeReviewSnapshots)
        let records = snapshots.map { snapshot in
            MCPSharedCodeReviewSessionRecord(
                sessionId: snapshot.sessionId,
                conversationId: snapshot.conversationId?.uuidString.lowercased(),
                phase: snapshot.phase.rawValue,
                stage: snapshot.stage.rawValue,
                findingsCount: snapshot.findings.count,
                openFindingsCount: snapshot.openFindings.count,
                currentRound: snapshot.currentRound,
                activeWorkerCount: snapshot.activeWorkerCount,
                scopeType: snapshot.scope?.type.rawValue,
                scopeRef: snapshot.scope?.ref,
                startedAt: snapshot.startedAt,
                updatedAt: snapshot.lastUpdatedAt,
                isActive: snapshot.isActive
            )
        }

        var latestSessionIdByConversation: [String: String] = [:]
        for snapshot in snapshots {
            guard let conversationId = snapshot.conversationId?.uuidString.lowercased(),
                  latestSessionIdByConversation[conversationId] == nil else {
                continue
            }
            latestSessionIdByConversation[conversationId] = snapshot.sessionId
        }

        return MCPSharedCodeReviewIndex(
            latestSessionId: snapshots.first?.sessionId,
            latestSessionIdByConversation: latestSessionIdByConversation,
            sessions: records
        )
    }

    private static func ensureCodeReviewDirectories() {
        ensureDirectory()
        let directories = [codeReviewDirectoryPath, codeReviewSessionsDirectoryPath]
        for directory in directories where !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private static func sortCodeReviewSnapshots(
        _ lhs: CodeReviewSessionSnapshot,
        _ rhs: CodeReviewSessionSnapshot
    ) -> Bool {
        if lhs.mutationSequence != rhs.mutationSequence {
            return lhs.mutationSequence > rhs.mutationSequence
        }
        if lhs.lastUpdatedAt != rhs.lastUpdatedAt {
            return lhs.lastUpdatedAt > rhs.lastUpdatedAt
        }
        return lhs.sessionId > rhs.sessionId
    }

    private static func shouldSkipCodeReviewSnapshotWrite(
        current: CodeReviewSessionSnapshot,
        incoming: CodeReviewSessionSnapshot
    ) -> Bool {
        if incoming.mutationSequence != current.mutationSequence {
            return incoming.mutationSequence < current.mutationSequence
        }
        return incoming.lastUpdatedAt < current.lastUpdatedAt
    }
}
