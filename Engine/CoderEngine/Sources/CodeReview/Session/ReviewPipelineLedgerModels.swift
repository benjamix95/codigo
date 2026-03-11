import Foundation

public enum ReviewPipelineLedgerStatus: String, Sendable, Codable, CaseIterable {
    case pending
    case running
    case completed
    case blocked
}

public struct ReviewPipelinePhaseLedgerEntry: Sendable, Codable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let status: ReviewPipelineLedgerStatus
    public let fileCount: Int
    public let workerCount: Int
    public let findingsCount: Int
    public let startedAt: Date?
    public let completedAt: Date?
    public let summary: String?

    public init(
        id: String,
        title: String,
        status: ReviewPipelineLedgerStatus,
        fileCount: Int = 0,
        workerCount: Int = 0,
        findingsCount: Int = 0,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        summary: String? = nil
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.fileCount = fileCount
        self.workerCount = workerCount
        self.findingsCount = findingsCount
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.summary = summary
    }
}

public struct ReviewPipelineFileLedgerEntry: Sendable, Codable, Equatable, Identifiable {
    public let path: String
    public let phaseId: String
    public let status: ReviewPipelineLedgerStatus
    public let workerIds: [String]
    public let toolIds: [String]
    public let severity: FindingSeverity?
    public let candidateCount: Int
    public let findingCount: Int
    public let patchReadyCount: Int
    public let summary: String?

    public var id: String { path }

    public init(
        path: String,
        phaseId: String,
        status: ReviewPipelineLedgerStatus,
        workerIds: [String] = [],
        toolIds: [String] = [],
        severity: FindingSeverity? = nil,
        candidateCount: Int = 0,
        findingCount: Int = 0,
        patchReadyCount: Int = 0,
        summary: String? = nil
    ) {
        self.path = path
        self.phaseId = phaseId
        self.status = status
        self.workerIds = workerIds
        self.toolIds = toolIds
        self.severity = severity
        self.candidateCount = candidateCount
        self.findingCount = findingCount
        self.patchReadyCount = patchReadyCount
        self.summary = summary
    }
}
