import CryptoKit
import Foundation

struct VerifiedFindingsDeltaCheckpoint: Codable, Equatable {
    let sessionId: String
    let eventSchemaVersion: Int
    let projectionSchemaVersion: Int
    let entitySchemaVersion: Int
    let lastUpdatedAt: Date
    let checkpointedAt: Date
    let runHashes: [String: String]
    let findingHashes: [String: String]
    let evidenceHashes: [String: String]
    let verificationReportHashes: [String: String]
    let patchArtifactHashes: [String: String]
    let revalidationReportHashes: [String: String]
    let eventHashes: [String: String]
    let commandLogHashes: [String: String]
    let traceHash: String
}

struct VerifiedFindingsCompactCanonicalMetadata: Codable, Equatable {
    let runIds: [String]
    let findingIds: [String]
    let evidenceIds: [String]
    let verificationReportIds: [String]
    let patchArtifactIds: [String]
    let revalidationReportIds: [String]
    let eventIds: [String]
    let commandIds: [String]
    let traceCount: Int
}

struct ArtifactPayloadPlaceholder {
    let id: String
    let contentText: String
    let containsSensitiveData: Bool
    let redactionApplied: Bool
    let retentionClass: String
    let visibilityLevel: String

    func merging(with other: ArtifactPayloadPlaceholder) -> ArtifactPayloadPlaceholder {
        ArtifactPayloadPlaceholder(
            id: id,
            contentText: contentText,
            containsSensitiveData: containsSensitiveData || other.containsSensitiveData,
            redactionApplied: redactionApplied || other.redactionApplied,
            retentionClass: other.retentionClass,
            visibilityLevel: other.visibilityLevel
        )
    }
}
