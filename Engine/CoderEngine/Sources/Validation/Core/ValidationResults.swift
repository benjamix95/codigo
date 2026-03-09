import Foundation

public struct ValidationFailure: Sendable, Codable, Equatable {
    public let stage: ValidationStageID
    public let message: String

    public init(stage: ValidationStageID, message: String) {
        self.stage = stage
        self.message = message
    }
}

public struct ValidationStageResult: Sendable, Codable, Equatable {
    public let stage: ValidationStageID
    public let status: ValidationStageStatus
    public let summary: String
    public let command: String?
    public let logExcerpt: String?

    public init(
        stage: ValidationStageID,
        status: ValidationStageStatus,
        summary: String,
        command: String? = nil,
        logExcerpt: String? = nil
    ) {
        self.stage = stage
        self.status = status
        self.summary = summary
        self.command = command
        self.logExcerpt = logExcerpt
    }
}

public struct ValidationRunResult: Sendable, Codable, Equatable {
    public let runId: String
    public let profile: ValidationProfile
    public let status: ValidationStatus
    public let touchedFiles: [String]
    public let stageResults: [ValidationStageResult]
    public let durationMs: Int
    public let failure: ValidationFailure?

    public init(
        runId: String,
        profile: ValidationProfile,
        status: ValidationStatus,
        touchedFiles: [String],
        stageResults: [ValidationStageResult],
        durationMs: Int,
        failure: ValidationFailure?
    ) {
        self.runId = runId
        self.profile = profile
        self.status = status
        self.touchedFiles = touchedFiles
        self.stageResults = stageResults
        self.durationMs = durationMs
        self.failure = failure
    }

    public var summaryLine: String {
        let base = "validation \(status.rawValue) [\(profile.rawValue)]"
        guard let failure else { return base }
        return "\(base): \(failure.stage.rawValue) — \(failure.message)"
    }
}
