import Foundation

public struct VerifiedCommandDeduplicationRecord: Sendable, Codable, Equatable {
    public let commandId: String
    public let requestFingerprint: String
    public let entityId: String
    public let resultSummary: String
    public let recordedAt: Date
}

public struct VerifiedFindingListItemProjection: Sendable, Codable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let domain: VerifiedFindingDomain
    public let status: VerifiedFindingStatus
    public let staleStatus: VerifiedFindingStaleStatus
    public let severity: VerifiedFindingSeverity
    public let filePath: String
    public let lineStart: Int?
    public let duplicateOf: [String]
    public let mergedIntoFindingId: String?
    public let recurrenceGroupId: String?

    public init(id: String, title: String, domain: VerifiedFindingDomain, status: VerifiedFindingStatus, staleStatus: VerifiedFindingStaleStatus, severity: VerifiedFindingSeverity, filePath: String, lineStart: Int?, duplicateOf: [String], mergedIntoFindingId: String?, recurrenceGroupId: String?) {
        self.id = id
        self.title = title
        self.domain = domain
        self.status = status
        self.staleStatus = staleStatus
        self.severity = severity
        self.filePath = filePath
        self.lineStart = lineStart
        self.duplicateOf = duplicateOf
        self.mergedIntoFindingId = mergedIntoFindingId
        self.recurrenceGroupId = recurrenceGroupId
    }
}

public struct VerifiedFindingsProjectionSnapshot: Sendable, Codable, Equatable {
    public let candidateQueue: [VerifiedFindingListItemProjection]
    public let verifiedQueue: [VerifiedFindingListItemProjection]
    public let duplicatesCount: Int
    public let staleCandidatesCount: Int
    public let traceSnippets: [String]

    public init(candidateQueue: [VerifiedFindingListItemProjection], verifiedQueue: [VerifiedFindingListItemProjection], duplicatesCount: Int, staleCandidatesCount: Int, traceSnippets: [String]) {
        self.candidateQueue = candidateQueue
        self.verifiedQueue = verifiedQueue
        self.duplicatesCount = duplicatesCount
        self.staleCandidatesCount = staleCandidatesCount
        self.traceSnippets = traceSnippets
    }
}

public struct VerifiedFindingsCanonicalSnapshot: Sendable, Codable, Equatable {
    public let runs: [String: VerifiedPipelineRun]
    public let findings: [String: VerifiedFinding]
    public let evidences: [String: VerifiedEvidence]
    public let verificationReports: [String: VerifiedVerificationReport]
    public let patchArtifacts: [String: VerifiedPatchArtifact]
    public let revalidationReports: [String: VerifiedRevalidationReport]
    public let commandLog: [VerifiedCommandDeduplicationRecord]
    public let eventLog: [VerifiedPipelineEvent]
    public let traceLog: [String]

    public init(
        runs: [String: VerifiedPipelineRun],
        findings: [String: VerifiedFinding],
        evidences: [String: VerifiedEvidence],
        verificationReports: [String: VerifiedVerificationReport],
        patchArtifacts: [String: VerifiedPatchArtifact],
        revalidationReports: [String: VerifiedRevalidationReport],
        commandLog: [VerifiedCommandDeduplicationRecord],
        eventLog: [VerifiedPipelineEvent],
        traceLog: [String]
    ) {
        self.runs = runs
        self.findings = findings
        self.evidences = evidences
        self.verificationReports = verificationReports
        self.patchArtifacts = patchArtifacts
        self.revalidationReports = revalidationReports
        self.commandLog = commandLog
        self.eventLog = eventLog
        self.traceLog = traceLog
    }
}

public actor VerifiedFindingsCanonicalStore {
    private var runs: [String: VerifiedPipelineRun] = [:]
    private var findings: [String: VerifiedFinding] = [:]
    private var evidences: [String: VerifiedEvidence] = [:]
    private var verificationReports: [String: VerifiedVerificationReport] = [:]
    private var patchArtifacts: [String: VerifiedPatchArtifact] = [:]
    private var revalidationReports: [String: VerifiedRevalidationReport] = [:]
    private var commandLog: [VerifiedCommandDeduplicationRecord] = []
    private var eventLog: [VerifiedPipelineEvent] = []
    private var traceLog: [String] = []

    public init() {}

    public func upsert(run: VerifiedPipelineRun) { runs[run.id] = run }
    public func upsert(finding: VerifiedFinding) { findings[finding.id] = finding }
    public func upsert(evidence: VerifiedEvidence) { evidences[evidence.id] = evidence }
    public func upsert(report: VerifiedVerificationReport) { verificationReports[report.id] = report }
    public func upsert(patch: VerifiedPatchArtifact) { patchArtifacts[patch.id] = patch }
    public func upsert(revalidation: VerifiedRevalidationReport) { revalidationReports[revalidation.id] = revalidation }
    public func append(commandRecord: VerifiedCommandDeduplicationRecord) { commandLog.append(commandRecord) }
    public func append(event: VerifiedPipelineEvent) { eventLog.append(event) }
    public func append(trace: String) { traceLog.append(trace) }

    public func snapshot() -> VerifiedFindingsCanonicalSnapshot {
        VerifiedFindingsCanonicalSnapshot(
            runs: runs,
            findings: findings,
            evidences: evidences,
            verificationReports: verificationReports,
            patchArtifacts: patchArtifacts,
            revalidationReports: revalidationReports,
            commandLog: commandLog,
            eventLog: eventLog,
            traceLog: traceLog
        )
    }
}

struct ReviewPatchRustRequest: Encodable {
    let schemaVersion: Int
    let operation: String
    let action: String
    let sessionId: String
    let findingId: String
    let conversationId: String?
    let snapshot: ReviewPatchRustSnapshot
}

public struct ReviewPatchRuntimeStartRequest: Encodable {
    public let schemaVersion: Int
    public let action: String
    public let sessionId: String
    public let findingId: String
    public let conversationId: String?
    public let snapshot: ReviewPatchRustSnapshot

    public init(
        schemaVersion: Int,
        action: String,
        sessionId: String,
        findingId: String,
        conversationId: String?,
        snapshot: ReviewPatchRustSnapshot
    ) {
        self.schemaVersion = schemaVersion
        self.action = action
        self.sessionId = sessionId
        self.findingId = findingId
        self.conversationId = conversationId
        self.snapshot = snapshot
    }
}

public struct ReviewPatchRuntimeResultRequest: Encodable {
    public let schemaVersion: Int
    public let runtimeId: String
    public let succeeded: Bool
    public let errorMessage: String?

    public init(
        schemaVersion: Int,
        runtimeId: String,
        succeeded: Bool,
        errorMessage: String?
    ) {
        self.schemaVersion = schemaVersion
        self.runtimeId = runtimeId
        self.succeeded = succeeded
        self.errorMessage = errorMessage
    }
}

struct ReviewPatchRuntimeStateRequest: Encodable {
    let schemaVersion: Int
    let runtimeId: String
}

public struct ReviewPatchRustSnapshot: Encodable {
    public let sessionId: String
    public let conversationId: String?
    public let findingIds: [String]
    public let candidateIds: [String]
    public let patches: [ReviewPatchRustPatch]
    public let findings: [ReviewPatchRustFinding]

    public init(snapshot: CodeReviewSessionSnapshot) {
        self.sessionId = snapshot.sessionId
        self.conversationId = snapshot.conversationId?.uuidString.lowercased()
        self.findingIds = snapshot.findings.map(\.id)
        self.candidateIds = snapshot.candidates.map(\.id)
        self.patches = snapshot.patches.map {
            ReviewPatchRustPatch(
                id: $0.id,
                findingId: $0.findingId,
                status: $0.status.rawValue,
                verifyStatus: $0.verifyStatus.rawValue,
                validationStatus: $0.validationStatus.rawValue,
                riskScore: $0.riskScore
            )
        }
        self.findings = snapshot.findings.map {
            ReviewPatchRustFinding(
                id: $0.id,
                status: $0.status.rawValue,
                severity: $0.severity.rawValue,
                category: $0.category.rawValue,
                message: $0.message,
                patchArtifactId: $0.patchArtifactId
            )
        }
    }
}

public struct ReviewPatchRustPatch: Encodable {
    public let id: String
    public let findingId: String
    public let status: String
    public let verifyStatus: String
    public let validationStatus: String
    public let riskScore: Double

    public init(
        id: String,
        findingId: String,
        status: String,
        verifyStatus: String,
        validationStatus: String,
        riskScore: Double
    ) {
        self.id = id
        self.findingId = findingId
        self.status = status
        self.verifyStatus = verifyStatus
        self.validationStatus = validationStatus
        self.riskScore = riskScore
    }
}

public struct ReviewPatchRustFinding: Encodable {
    public let id: String
    public let status: String
    public let severity: String
    public let category: String
    public let message: String
    public let patchArtifactId: String?

    public init(
        id: String,
        status: String,
        severity: String,
        category: String,
        message: String,
        patchArtifactId: String?
    ) {
        self.id = id
        self.status = status
        self.severity = severity
        self.category = category
        self.message = message
        self.patchArtifactId = patchArtifactId
    }
}

public struct ReviewPatchRustResponse: Decodable {
    public let isError: Bool
    public let errorCode: String?
    public let errorMessage: String?
    public let steps: [String]
    public let patchId: String?
    public let patchVerifyStatus: String?
    public let patchRiskScore: Double?
    public let findingSeverity: String?
    public let findingCategory: String?
    public let findingMessage: String?
}

public struct ReviewPatchRuntimeResponse: Decodable {
    public let isError: Bool
    public let errorCode: String?
    public let errorMessage: String?
    public let runtimeId: String?
    public let status: String
    public let currentStep: String?
}
