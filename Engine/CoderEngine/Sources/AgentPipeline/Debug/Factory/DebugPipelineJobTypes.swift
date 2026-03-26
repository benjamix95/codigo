import Foundation

// MARK: - DebugSessionRequest

public struct DebugSessionRequest: Sendable, Equatable {
    public var errorSummary: String
    public var workspaceHints: [String]
    public var targetPath: String?
    public var arguments: [String]
    public var breakpoints: [DebugNativeBreakpointSpec]
    public var watchExpressions: [String]
    public var backendPolicy: DebugBackendPolicy
    public var includeReviewStage: Bool
    public var includeCleanupStage: Bool
    public var includeNativeStages: Bool

    public init(
        errorSummary: String,
        workspaceHints: [String] = [],
        targetPath: String? = nil,
        arguments: [String] = [],
        breakpoints: [DebugNativeBreakpointSpec] = [],
        watchExpressions: [String] = [],
        backendPolicy: DebugBackendPolicy = .hybrid,
        includeReviewStage: Bool = true,
        includeCleanupStage: Bool = true,
        includeNativeStages: Bool = false
    ) {
        self.errorSummary = errorSummary
        self.workspaceHints = workspaceHints
        self.targetPath = targetPath
        self.arguments = arguments
        self.breakpoints = breakpoints
        self.watchExpressions = watchExpressions
        self.backendPolicy = backendPolicy
        self.includeReviewStage = includeReviewStage
        self.includeCleanupStage = includeCleanupStage
        self.includeNativeStages = includeNativeStages
    }
}

public enum DebugPipelineSlice: String, Sendable, Equatable {
    case intake
    case investigation
    case resolution
    case full
}
