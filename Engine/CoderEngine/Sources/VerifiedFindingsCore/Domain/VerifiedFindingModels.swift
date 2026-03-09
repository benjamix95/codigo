import Foundation

public struct VerifiedCommandMeta: Sendable, Codable, Equatable {
    public let commandId: String
    public let entityId: String
    public let issuedBy: String
    public let issuedFrom: VerifiedFindingOriginEntryPoint
    public let issuedAt: Date
    public let requestFingerprint: String
    public let expectedEntityVersion: Int?

    public init(
        commandId: String = UUID().uuidString.lowercased(),
        entityId: String,
        issuedBy: String,
        issuedFrom: VerifiedFindingOriginEntryPoint,
        issuedAt: Date = Date(),
        requestFingerprint: String,
        expectedEntityVersion: Int? = nil
    ) {
        self.commandId = commandId
        self.entityId = entityId
        self.issuedBy = issuedBy
        self.issuedFrom = issuedFrom
        self.issuedAt = issuedAt
        self.requestFingerprint = requestFingerprint
        self.expectedEntityVersion = expectedEntityVersion
    }
}

public struct VerifiedFinding: Sendable, Codable, Identifiable, Equatable {
    public let id: String
    public let domain: VerifiedFindingDomain
    public let title: String
    public let summary: String
    public let category: String
    public let severity: VerifiedFindingSeverity
    public let confidence: Double
    public let status: VerifiedFindingStatus
    public let filePath: String
    public let lineStart: Int?
    public let lineEnd: Int?
    public let ruleId: String?
    public let evidenceIds: [String]
    public let verificationReportId: String?
    public let patchId: String?
    public let revalidationReportId: String?
    public let rootCause: String?
    public let impact: String?
    public let exploitability: String?
    public let reproducibility: VerifiedFindingReproducibility
    public let version: Int
    public let originEntryPoint: VerifiedFindingOriginEntryPoint
    public let sourceOrigin: String?
    public let lastCommandId: String?
    public let staleStatus: VerifiedFindingStaleStatus
    public let closedReason: String?
    public let policyFlags: [String]
    public let findingFingerprint: String
    public let identityVersion: Int
    public let possibleDuplicateOf: [String]
    public let mergedIntoFindingId: String?
    public let recurrenceGroupId: String?
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: String = UUID().uuidString.lowercased(),
        domain: VerifiedFindingDomain,
        title: String,
        summary: String,
        category: String,
        severity: VerifiedFindingSeverity,
        confidence: Double,
        status: VerifiedFindingStatus,
        filePath: String,
        lineStart: Int? = nil,
        lineEnd: Int? = nil,
        ruleId: String? = nil,
        evidenceIds: [String] = [],
        verificationReportId: String? = nil,
        patchId: String? = nil,
        revalidationReportId: String? = nil,
        rootCause: String? = nil,
        impact: String? = nil,
        exploitability: String? = nil,
        reproducibility: VerifiedFindingReproducibility = .none,
        version: Int = 1,
        originEntryPoint: VerifiedFindingOriginEntryPoint,
        sourceOrigin: String? = nil,
        lastCommandId: String? = nil,
        staleStatus: VerifiedFindingStaleStatus = .active,
        closedReason: String? = nil,
        policyFlags: [String] = [],
        findingFingerprint: String,
        identityVersion: Int = 1,
        possibleDuplicateOf: [String] = [],
        mergedIntoFindingId: String? = nil,
        recurrenceGroupId: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.domain = domain
        self.title = title
        self.summary = summary
        self.category = category
        self.severity = severity
        self.confidence = confidence
        self.status = status
        self.filePath = filePath
        self.lineStart = lineStart
        self.lineEnd = lineEnd
        self.ruleId = ruleId
        self.evidenceIds = evidenceIds
        self.verificationReportId = verificationReportId
        self.patchId = patchId
        self.revalidationReportId = revalidationReportId
        self.rootCause = rootCause
        self.impact = impact
        self.exploitability = exploitability
        self.reproducibility = reproducibility
        self.version = version
        self.originEntryPoint = originEntryPoint
        self.sourceOrigin = sourceOrigin
        self.lastCommandId = lastCommandId
        self.staleStatus = staleStatus
        self.closedReason = closedReason
        self.policyFlags = policyFlags
        self.findingFingerprint = findingFingerprint
        self.identityVersion = identityVersion
        self.possibleDuplicateOf = possibleDuplicateOf
        self.mergedIntoFindingId = mergedIntoFindingId
        self.recurrenceGroupId = recurrenceGroupId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct VerifiedEvidence: Sendable, Codable, Identifiable, Equatable {
    public let id: String
    public let findingId: String
    public let type: VerifiedEvidenceType
    public let source: String
    public let summary: String
    public let payloadRef: String
    public let originTool: String
    public let originCommandId: String
    public let originRunId: String
    public let originStep: String
    public let sourceType: VerifiedEvidenceSourceType
    public let capturedAt: Date
    public let artifactRef: String
    public let hashOrFingerprint: String
    public let containsSensitiveData: Bool
    public let redactionApplied: Bool
    public let redactionReason: String?
    public let retentionClass: VerifiedRetentionClass
    public let visibilityLevel: VerifiedVisibilityLevel
    public let createdAt: Date
}

public struct VerifiedVerificationReport: Sendable, Codable, Identifiable, Equatable {
    public let id: String
    public let findingId: String
    public let verifierType: String
    public let verdict: VerificationVerdict
    public let confidence: Double
    public let steps: [String]
    public let commandLogRefs: [String]
    public let evidenceIds: [String]
    public let reasoningSummary: String
    public let errorCategory: VerifiedFailureCategory?
    public let failureReasonCode: String?
    public let retryable: Bool
    public let failurePhase: VerifiedFailurePhase?
    public let retryCount: Int
    public let maxRetryAllowed: Int
    public let createdAt: Date
}
