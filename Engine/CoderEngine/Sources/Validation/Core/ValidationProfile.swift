import Foundation

public enum ValidationTrigger: String, Sendable, Codable, CaseIterable {
    case reviewPatchPreview
    case reviewPatchApply
    case gitCommit
    case ciFull
}

public enum ValidationProfile: String, Sendable, Codable, CaseIterable {
    case reviewPatchPreview
    case reviewPatchApply
    case gitCommit
    case ciFull
}

public enum ValidationStageID: String, Sendable, Codable, CaseIterable {
    case patchSafety
    case codeSize
    case build
    case targetedTests
    case security
    case regression
    /// `xcodebuild test` sullo scheme configurato senza filtri `-only-testing` (tutti i bundle dello scheme).
    case fullSchemeTests
    case performance
    case e2e
}

public enum ValidationStageStatus: String, Sendable, Codable {
    case passed
    case failed
    case skipped
}

public enum ValidationStatus: String, Sendable, Codable {
    case pending
    case passed
    case failed
}
