import Foundation

extension MCPSharedState {
    public static var verifiedFindingsDirectoryPath: URL {
        sharedDirectory.appendingPathComponent("verified-findings")
    }

    public static var verifiedFindingsSessionsDirectoryPath: URL {
        verifiedFindingsDirectoryPath.appendingPathComponent("sessions")
    }

    public static func verifiedFindingsEnvelopeFilePath(sessionId: String) -> URL {
        verifiedFindingsSessionsDirectoryPath.appendingPathComponent("\(sessionId).json")
    }

    public static func writeVerifiedFindingsEnvelope(
        _ envelope: VerifiedFindingsSessionEnvelope
    ) {
        withCodeReviewFileLock {
            _writeVerifiedFindingsEnvelopeUnsafe(envelope)
        }
    }

    public static func readVerifiedFindingsEnvelope(
        sessionId: String
    ) -> VerifiedFindingsSessionEnvelope? {
        withCodeReviewFileLock {
            _readVerifiedFindingsEnvelopeUnsafe(sessionId: sessionId)
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

    static func deleteVerifiedFindingsEnvelopeUnsafe(sessionId: String) {
        guard let safeSessionId = sanitizedCodeReviewSessionId(sessionId) else { return }
        try? FileManager.default.removeItem(
            at: verifiedFindingsEnvelopeFilePath(sessionId: safeSessionId)
        )
    }

    static func ensureVerifiedFindingsDirectories() {
        let directories = [verifiedFindingsDirectoryPath, verifiedFindingsSessionsDirectoryPath]
        for directory in directories where !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }
}
