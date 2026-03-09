import Foundation

public struct MCPSharedVerifiedFindingsCheckpoint: Codable, Sendable, Equatable {
    public let sessionId: String
    public let eventSchemaVersion: Int
    public let projectionSchemaVersion: Int
    public let entitySchemaVersion: Int
    public let checkpointedAt: Date
    public let findingCount: Int
    public let eventCount: Int
    public let traceCount: Int
}

extension MCPSharedState {
    public static var verifiedFindingsDirectoryPath: URL {
        sharedDirectory.appendingPathComponent("verified-findings")
    }

    public static var verifiedFindingsSessionsDirectoryPath: URL {
        verifiedFindingsDirectoryPath.appendingPathComponent("sessions")
    }

    public static var verifiedFindingsCanonicalDirectoryPath: URL {
        verifiedFindingsDirectoryPath.appendingPathComponent("canonical")
    }

    public static var verifiedFindingsCheckpointsDirectoryPath: URL {
        verifiedFindingsDirectoryPath.appendingPathComponent("checkpoints")
    }

    public static func verifiedFindingsEnvelopeFilePath(sessionId: String) -> URL {
        verifiedFindingsSessionsDirectoryPath.appendingPathComponent("\(sessionId).json")
    }

    public static func verifiedFindingsCanonicalSnapshotFilePath(sessionId: String) -> URL {
        verifiedFindingsCanonicalDirectoryPath.appendingPathComponent("\(sessionId).json")
    }

    public static func verifiedFindingsCheckpointFilePath(sessionId: String) -> URL {
        verifiedFindingsCheckpointsDirectoryPath.appendingPathComponent("\(sessionId).json")
    }

    public static func writeVerifiedFindingsEnvelope(
        _ envelope: VerifiedFindingsSessionEnvelope
    ) {
        if let store = persistenceStoreIfAvailable() {
            try? store.persistVerifiedFindingsEnvelope(envelope)
        }
        withCodeReviewFileLock {
            _writeVerifiedFindingsEnvelopeUnsafe(envelope)
        }
    }

    public static func readVerifiedFindingsEnvelope(
        sessionId: String
    ) -> VerifiedFindingsSessionEnvelope? {
        if let envelope = readVerifiedFindingsEnvelopeFromPersistence(sessionId: sessionId) {
            return envelope
        }
        return withCodeReviewFileLock {
            _readVerifiedFindingsEnvelopeUnsafe(sessionId: sessionId)
                ?? _rebuildVerifiedFindingsEnvelopeUnsafe(sessionId: sessionId)
        }
    }

    public static func readVerifiedFindingsCanonicalSnapshot(
        sessionId: String
    ) -> VerifiedFindingsCanonicalSnapshot? {
        if let envelope = readVerifiedFindingsEnvelopeFromPersistence(sessionId: sessionId) {
            return envelope.canonicalSnapshot
        }
        return withCodeReviewFileLock {
            _readVerifiedFindingsCanonicalSnapshotUnsafe(sessionId: sessionId)
        }
    }

    public static func readVerifiedFindingsCheckpoint(
        sessionId: String
    ) -> MCPSharedVerifiedFindingsCheckpoint? {
        if let checkpoint = readVerifiedFindingsCheckpointFromPersistence(sessionId: sessionId) {
            return checkpoint
        }
        return withCodeReviewFileLock {
            _readVerifiedFindingsCheckpointUnsafe(sessionId: sessionId)
        }
    }

    static func _writeVerifiedFindingsEnvelopeUnsafe(
        _ envelope: VerifiedFindingsSessionEnvelope
    ) {
        ensureVerifiedFindingsDirectories()
        guard let safeSessionId = sanitizedCodeReviewSessionId(envelope.sessionId) else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(envelope) else { return }
        try? data.write(
            to: verifiedFindingsEnvelopeFilePath(sessionId: safeSessionId),
            options: .atomic
        )
        _writeVerifiedFindingsCanonicalSnapshotUnsafe(
            envelope.canonicalSnapshot,
            sessionId: safeSessionId
        )
        _writeVerifiedFindingsCheckpointUnsafe(
            MCPSharedVerifiedFindingsCheckpoint(
                sessionId: safeSessionId,
                eventSchemaVersion: envelope.eventSchemaVersion,
                projectionSchemaVersion: envelope.projectionSchemaVersion,
                entitySchemaVersion: envelope.entitySchemaVersion,
                checkpointedAt: Date(),
                findingCount: envelope.canonicalSnapshot.findings.count,
                eventCount: envelope.canonicalSnapshot.eventLog.count,
                traceCount: envelope.canonicalSnapshot.traceLog.count
            ),
            sessionId: safeSessionId
        )
    }

    static func _readVerifiedFindingsEnvelopeUnsafe(
        sessionId: String
    ) -> VerifiedFindingsSessionEnvelope? {
        guard let safeSessionId = sanitizedCodeReviewSessionId(sessionId) else { return nil }
        let url = verifiedFindingsEnvelopeFilePath(sessionId: safeSessionId)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(VerifiedFindingsSessionEnvelope.self, from: data)
    }

    static func _writeVerifiedFindingsCanonicalSnapshotUnsafe(
        _ snapshot: VerifiedFindingsCanonicalSnapshot,
        sessionId: String
    ) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(
            to: verifiedFindingsCanonicalSnapshotFilePath(sessionId: sessionId),
            options: .atomic
        )
    }

    static func _readVerifiedFindingsCanonicalSnapshotUnsafe(
        sessionId: String
    ) -> VerifiedFindingsCanonicalSnapshot? {
        guard let safeSessionId = sanitizedCodeReviewSessionId(sessionId) else { return nil }
        let url = verifiedFindingsCanonicalSnapshotFilePath(sessionId: safeSessionId)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(VerifiedFindingsCanonicalSnapshot.self, from: data)
    }

    static func _writeVerifiedFindingsCheckpointUnsafe(
        _ checkpoint: MCPSharedVerifiedFindingsCheckpoint,
        sessionId: String
    ) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(checkpoint) else { return }
        try? data.write(
            to: verifiedFindingsCheckpointFilePath(sessionId: sessionId),
            options: .atomic
        )
    }

    static func _readVerifiedFindingsCheckpointUnsafe(
        sessionId: String
    ) -> MCPSharedVerifiedFindingsCheckpoint? {
        guard let safeSessionId = sanitizedCodeReviewSessionId(sessionId) else { return nil }
        let url = verifiedFindingsCheckpointFilePath(sessionId: safeSessionId)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(MCPSharedVerifiedFindingsCheckpoint.self, from: data)
    }

    static func _rebuildVerifiedFindingsEnvelopeUnsafe(
        sessionId: String
    ) -> VerifiedFindingsSessionEnvelope? {
        guard let safeSessionId = sanitizedCodeReviewSessionId(sessionId),
              let canonicalSnapshot = _readVerifiedFindingsCanonicalSnapshotUnsafe(sessionId: safeSessionId) else {
            return nil
        }
        let checkpoint = _readVerifiedFindingsCheckpointUnsafe(sessionId: safeSessionId)
        return VerifiedFindingsSessionEnvelope(
            sessionId: safeSessionId,
            canonicalSnapshot: canonicalSnapshot,
            projectionSnapshot: VerifiedFindingsProjectionBuilder.build(from: canonicalSnapshot),
            eventSchemaVersion: checkpoint?.eventSchemaVersion ?? 1,
            projectionSchemaVersion: checkpoint?.projectionSchemaVersion ?? 1,
            entitySchemaVersion: checkpoint?.entitySchemaVersion ?? 1,
            lastUpdatedAt: checkpoint?.checkpointedAt ?? Date()
        )
    }

    static func deleteVerifiedFindingsEnvelopeUnsafe(sessionId: String) {
        guard let safeSessionId = sanitizedCodeReviewSessionId(sessionId) else { return }
        let urls = [
            verifiedFindingsEnvelopeFilePath(sessionId: safeSessionId),
            verifiedFindingsCanonicalSnapshotFilePath(sessionId: safeSessionId),
            verifiedFindingsCheckpointFilePath(sessionId: safeSessionId),
        ]
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
    }

    static func ensureVerifiedFindingsDirectories() {
        let directories = [
            verifiedFindingsDirectoryPath,
            verifiedFindingsSessionsDirectoryPath,
            verifiedFindingsCanonicalDirectoryPath,
            verifiedFindingsCheckpointsDirectoryPath,
        ]
        for directory in directories where !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}
