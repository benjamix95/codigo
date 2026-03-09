import Foundation

public struct VerifiedCommandDeduplicationRecord: Sendable, Codable, Equatable {
    public let commandId: String
    public let requestFingerprint: String
    public let entityId: String
    public let resultSummary: String
    public let recordedAt: Date
}

public actor CommandDeduplicationService {
    private var recordsByCommandId: [String: VerifiedCommandDeduplicationRecord] = [:]
    private var recordsByFingerprint: [String: VerifiedCommandDeduplicationRecord] = [:]

    public init() {}

    public func existingRecord(for meta: VerifiedCommandMeta) -> VerifiedCommandDeduplicationRecord? {
        if let byCommand = recordsByCommandId[meta.commandId] {
            return byCommand
        }
        return recordsByFingerprint[fingerprintKey(meta)]
    }

    public func record(
        meta: VerifiedCommandMeta,
        resultSummary: String,
        recordedAt: Date = Date()
    ) -> VerifiedCommandDeduplicationRecord {
        let record = VerifiedCommandDeduplicationRecord(
            commandId: meta.commandId,
            requestFingerprint: meta.requestFingerprint,
            entityId: meta.entityId,
            resultSummary: resultSummary,
            recordedAt: recordedAt
        )
        recordsByCommandId[meta.commandId] = record
        recordsByFingerprint[fingerprintKey(meta)] = record
        return record
    }

    private func fingerprintKey(_ meta: VerifiedCommandMeta) -> String {
        "\(meta.entityId)|\(meta.requestFingerprint)"
    }
}
