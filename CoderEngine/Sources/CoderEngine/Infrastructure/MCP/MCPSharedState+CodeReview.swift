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

    public static func writeCodeReviewSnapshot(_ snapshot: CodeReviewSessionSnapshot) {
        fileAccessQueue.sync {
            _writeCodeReviewSnapshotUnsafe(snapshot)
        }
    }

    public static func readCodeReviewIndex() -> MCPSharedCodeReviewIndex {
        fileAccessQueue.sync {
            _readCodeReviewIndexUnsafe()
        }
    }

    public static func readCodeReviewSnapshot(sessionId: String) -> CodeReviewSessionSnapshot? {
        fileAccessQueue.sync {
            _readCodeReviewSnapshotUnsafe(sessionId: sessionId)
        }
    }

    public static func readCodeReviewSnapshots(
        conversationId: UUID? = nil
    ) -> [CodeReviewSessionSnapshot] {
        fileAccessQueue.sync {
            let normalizedConversationId = conversationId?.uuidString.lowercased()
            let records = _readCodeReviewIndexUnsafe().sessions.filter { record in
                guard let normalizedConversationId else { return true }
                return record.conversationId == normalizedConversationId
            }
            return records
                .sorted(by: sortCodeReviewRecords)
                .compactMap { _readCodeReviewSnapshotUnsafe(sessionId: $0.sessionId) }
        }
    }

    public static func latestCodeReviewSessionId(
        conversationId: UUID? = nil
    ) -> String? {
        fileAccessQueue.sync {
            let index = _readCodeReviewIndexUnsafe()
            if let conversationId {
                return index.latestSessionIdByConversation[conversationId.uuidString.lowercased()]
            }
            return index.latestSessionId
        }
    }

    public static func readCodeReviewFindings(
        sessionId: String,
        severity: String? = nil,
        status: String? = nil,
        file: String? = nil,
        limit: Int = 50
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
        return Array(findings.prefix(limit)).map { $0.toPayload() }
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
            if let ref = scope.ref { payload["scope_ref"] = ref }
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
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshot) else {
            print("[MCPSharedState] ⚠️ Failed to encode code review snapshot")
            return
        }
        do {
            try data.write(
                to: codeReviewSessionFilePath(sessionId: snapshot.sessionId),
                options: .atomic
            )
            var index = _readCodeReviewIndexUnsafe()
            let record = MCPSharedCodeReviewSessionRecord(
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
            index.sessions.removeAll { $0.sessionId == snapshot.sessionId }
            index.sessions.insert(record, at: 0)
            index.latestSessionId = snapshot.sessionId
            if let conversationId = record.conversationId {
                index.latestSessionIdByConversation[conversationId] = snapshot.sessionId
            }
            _writeCodeReviewIndexUnsafe(index)
        } catch {
            print("[MCPSharedState] ⚠️ Failed to write code review snapshot: \(error.localizedDescription)")
        }
    }

    private static func _readCodeReviewIndexUnsafe() -> MCPSharedCodeReviewIndex {
        guard let data = try? Data(contentsOf: codeReviewIndexFilePath) else {
            return MCPSharedCodeReviewIndex()
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(MCPSharedCodeReviewIndex.self, from: data))
            ?? MCPSharedCodeReviewIndex()
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
        guard let data = try? Data(contentsOf: codeReviewSessionFilePath(sessionId: sessionId)) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CodeReviewSessionSnapshot.self, from: data)
    }

    private static func ensureCodeReviewDirectories() {
        ensureDirectory()
        let directories = [codeReviewDirectoryPath, codeReviewSessionsDirectoryPath]
        for directory in directories where !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private static func sortCodeReviewRecords(
        _ lhs: MCPSharedCodeReviewSessionRecord,
        _ rhs: MCPSharedCodeReviewSessionRecord
    ) -> Bool {
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        return lhs.sessionId > rhs.sessionId
    }
}
