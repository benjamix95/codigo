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
        if let store = persistenceStoreIfAvailable() {
            try? store.persistCodeReviewSnapshot(snapshot)
        }
        withCodeReviewFileLock {
            _writeCodeReviewSnapshotUnsafe(snapshot)
        }
    }

    public static func readCodeReviewIndex() -> MCPSharedCodeReviewIndex {
        if let store = persistenceStoreIfAvailable(),
           let snapshots = try? store.readCodeReviewSnapshots() {
            return buildCodeReviewIndex(snapshots: snapshots)
        }
        return withCodeReviewFileLock {
            rebuiltCodeReviewIndexUnsafe()
        }
    }

    public static func readCodeReviewSnapshot(sessionId: String) -> CodeReviewSessionSnapshot? {
        if let store = persistenceStoreIfAvailable(),
           let snapshot = try? store.readCodeReviewSnapshot(sessionId: sessionId) {
            return snapshot
        }
        return withCodeReviewFileLock {
            _readCodeReviewSnapshotUnsafe(sessionId: sessionId)
        }
    }

    public static func readCodeReviewSnapshots(
        conversationId: UUID? = nil
    ) -> [CodeReviewSessionSnapshot] {
        if let store = persistenceStoreIfAvailable(),
           let snapshots = try? store.readCodeReviewSnapshots(conversationId: conversationId) {
            return snapshots.sorted(by: sortCodeReviewSnapshots)
        }
        return withCodeReviewFileLock {
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

    public static func deleteCodeReviewSession(sessionId: String) {
        if let store = persistenceStoreIfAvailable() {
            try? store.deleteCodeReviewSession(sessionId: sessionId)
        }
        withCodeReviewFileLock {
            guard let snapshotFilePath = validatedCodeReviewSessionFilePath(sessionId: sessionId) else {
                return
            }
            try? FileManager.default.removeItem(at: snapshotFilePath)
            deleteVerifiedFindingsEnvelopeUnsafe(sessionId: sessionId)
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
        let data = ReviewPersistenceRustAdapter.encodeReviewSnapshot(snapshot)
            ?? (try? encoder.encode(snapshot))
        guard let data else {
            print("[MCPSharedState] ⚠️ Failed to encode code review snapshot")
            return
        }
        do {
            try data.write(
                to: snapshotFilePath,
                options: .atomic
            )
            if let verifiedFindings = snapshot.verifiedFindings {
                _writeVerifiedFindingsEnvelopeUnsafe(verifiedFindings)
            }
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
        guard var snapshot = ReviewPersistenceRustAdapter.decodeReviewSnapshot(from: data)
            ?? (try? decoder.decode(CodeReviewSessionSnapshot.self, from: data)) else {
            return nil
        }
        if snapshot.verifiedFindings == nil,
           let envelope = _readVerifiedFindingsEnvelopeUnsafe(sessionId: sessionId) {
            snapshot = snapshot.copying(verifiedFindings: envelope)
        }
        return snapshot
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

    static func redactedFindingReference(for finding: CodeReviewFinding) -> String {
        let ext = (finding.filePath as NSString).pathExtension.lowercased()
        let fileClass = ext.isEmpty ? "file" : "\(ext)-file"
        return "\(redactedFindingLabelPrefix)-\(fileClass)-\(stableRedactionSuffix(for: finding.filePath))"
    }

    static func redactedFindingSummary(for finding: CodeReviewFinding) -> String {
        let category = finding.category.rawValue.replacingOccurrences(of: "_", with: " ")
        return "Redacted \(finding.severity.rawValue) \(category) finding"
    }

    static func stableRedactionSuffix(for value: String) -> String {
        var hash: UInt32 = 2_166_136_261
        for byte in value.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 16_777_619
        }
        return String(format: "%08x", hash)
    }
}
