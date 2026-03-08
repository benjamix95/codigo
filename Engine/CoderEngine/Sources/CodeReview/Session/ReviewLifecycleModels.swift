import Foundation

public enum ReviewCandidateStatus: String, Sendable, Codable, CaseIterable {
    case new
    case verifying
    case verified
    case rejectedFalsePositive = "rejected_false_positive"
    case inconclusive
}

public enum ReviewSignalType: String, Sendable, Codable, CaseIterable {
    case pattern
    case semantic
    case testDerived = "test_derived"
    case llmVerified = "llm_verified"
    case manual
}

public struct ReviewCandidate: Sendable, Identifiable, Codable, Equatable {
    public let id: String
    public let severity: FindingSeverity
    public let category: FindingCategory
    public let origin: FindingOrigin
    public let filePath: String
    public let lineNumber: Int?
    public let endLineNumber: Int?
    public let message: String
    public let evidence: String?
    public let expectedInvariant: String?
    public let reproOrReasoning: String?
    public let confidence: Double?
    public let sourceTool: String?
    public let signalType: ReviewSignalType
    public var verificationStatus: ReviewCandidateStatus
    public var verificationMethod: String?
    public var verificationReport: String?
    public var falsePositiveReason: String?
    public let createdAt: Date
    public var verifiedAt: Date?

    public init(
        id: String = UUID().uuidString,
        severity: FindingSeverity,
        category: FindingCategory,
        origin: FindingOrigin,
        filePath: String,
        lineNumber: Int? = nil,
        endLineNumber: Int? = nil,
        message: String,
        evidence: String? = nil,
        expectedInvariant: String? = nil,
        reproOrReasoning: String? = nil,
        confidence: Double? = nil,
        sourceTool: String? = nil,
        signalType: ReviewSignalType = .semantic,
        verificationStatus: ReviewCandidateStatus = .new,
        verificationMethod: String? = nil,
        verificationReport: String? = nil,
        falsePositiveReason: String? = nil,
        createdAt: Date = Date(),
        verifiedAt: Date? = nil
    ) {
        self.id = id
        self.severity = severity
        self.category = category
        self.origin = origin
        self.filePath = filePath
        self.lineNumber = lineNumber
        self.endLineNumber = endLineNumber
        self.message = message
        self.evidence = evidence
        self.expectedInvariant = expectedInvariant
        self.reproOrReasoning = reproOrReasoning
        self.confidence = confidence
        self.sourceTool = sourceTool
        self.signalType = signalType
        self.verificationStatus = verificationStatus
        self.verificationMethod = verificationMethod
        self.verificationReport = verificationReport
        self.falsePositiveReason = falsePositiveReason
        self.createdAt = createdAt
        self.verifiedAt = verifiedAt
    }
}

public enum ReviewPatchStatus: String, Sendable, Codable, CaseIterable {
    case draft
    case verified
    case applied
    case applyFailed = "apply_failed"
    case prOpened = "pr_opened"
    case merged
    case conflict
    case rolledBack = "rolled_back"
}

public enum ReviewPatchVerifyStatus: String, Sendable, Codable, CaseIterable {
    case pending
    case verified
    case failed
    case skipped
}

public enum ReviewPatchPRStatus: String, Sendable, Codable, CaseIterable {
    case notRequested = "not_requested"
    case ready
    case opened
    case failed
}

public enum ReviewPatchMergeStatus: String, Sendable, Codable, CaseIterable {
    case notRequested = "not_requested"
    case pending
    case merged
    case failed
    case blocked
}

public struct ReviewPatchArtifact: Sendable, Identifiable, Codable, Equatable {
    public let id: String
    public let findingId: String
    public let patchText: String
    public let diffPreview: String
    public let touchedFiles: [String]
    public let riskScore: Double
    public var rollbackRef: String?
    public var status: ReviewPatchStatus
    public var verifyStatus: ReviewPatchVerifyStatus
    public var prStatus: ReviewPatchPRStatus
    public var mergeStatus: ReviewPatchMergeStatus
    public var conflicts: [String]
    public var worktreePath: String?
    public var branchName: String?
    public var baseBranchName: String?
    public var prURL: String?
    public var verificationReport: String?
    public var applyMessage: String?
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        findingId: String,
        patchText: String,
        diffPreview: String,
        touchedFiles: [String],
        riskScore: Double = 0,
        rollbackRef: String? = nil,
        status: ReviewPatchStatus = .draft,
        verifyStatus: ReviewPatchVerifyStatus = .pending,
        prStatus: ReviewPatchPRStatus = .notRequested,
        mergeStatus: ReviewPatchMergeStatus = .notRequested,
        conflicts: [String] = [],
        worktreePath: String? = nil,
        branchName: String? = nil,
        baseBranchName: String? = nil,
        prURL: String? = nil,
        verificationReport: String? = nil,
        applyMessage: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.findingId = findingId
        self.patchText = patchText
        self.diffPreview = diffPreview
        self.touchedFiles = touchedFiles
        self.riskScore = riskScore
        self.rollbackRef = rollbackRef
        self.status = status
        self.verifyStatus = verifyStatus
        self.prStatus = prStatus
        self.mergeStatus = mergeStatus
        self.conflicts = conflicts
        self.worktreePath = worktreePath
        self.branchName = branchName
        self.baseBranchName = baseBranchName
        self.prURL = prURL
        self.verificationReport = verificationReport
        self.applyMessage = applyMessage
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct ReviewSessionOutcome: Sendable, Codable, Equatable {
    public let summary: String
    public let verifiedFindings: Int
    public let falsePositives: Int
    public let patchesReady: Int
    public let patchesApplied: Int
    public let prsOpened: Int
    public let mergedPatches: Int
    public let conflictsDetected: Int
    public let manualActionRequired: Bool
    public let testsStatus: ReviewSessionTestStatus?
    public let generatedAt: Date

    public static let empty = ReviewSessionOutcome(
        summary: "No review outcome available yet.",
        verifiedFindings: 0,
        falsePositives: 0,
        patchesReady: 0,
        patchesApplied: 0,
        prsOpened: 0,
        mergedPatches: 0,
        conflictsDetected: 0,
        manualActionRequired: false,
        testsStatus: nil,
        generatedAt: .distantPast
    )

    public init(
        summary: String,
        verifiedFindings: Int,
        falsePositives: Int,
        patchesReady: Int,
        patchesApplied: Int,
        prsOpened: Int,
        mergedPatches: Int,
        conflictsDetected: Int,
        manualActionRequired: Bool,
        testsStatus: ReviewSessionTestStatus?,
        generatedAt: Date = Date()
    ) {
        self.summary = summary
        self.verifiedFindings = verifiedFindings
        self.falsePositives = falsePositives
        self.patchesReady = patchesReady
        self.patchesApplied = patchesApplied
        self.prsOpened = prsOpened
        self.mergedPatches = mergedPatches
        self.conflictsDetected = conflictsDetected
        self.manualActionRequired = manualActionRequired
        self.testsStatus = testsStatus
        self.generatedAt = generatedAt
    }
}
