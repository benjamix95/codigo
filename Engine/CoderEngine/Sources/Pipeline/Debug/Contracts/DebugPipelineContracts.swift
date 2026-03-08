import Foundation

// MARK: - DebugPipelinePhase

/// Fase semantica del flusso debug orchestrato.
public enum DebugPipelinePhase: String, Codable, Sendable, Equatable, CaseIterable {
    case idle
    case describing
    case reproducing
    case fixing
    case instrumenting
    case verifying
    case resolved
}

// MARK: - DebugBackendPolicy

/// Politica di esecuzione per la lane debug.
public enum DebugBackendPolicy: String, Codable, Sendable, Equatable, CaseIterable {
    case automatic
    case mcpOnly = "mcp_only"
    case nativeOnly = "native_only"
    case hybrid
    case appleHybrid = "apple_hybrid"
}

// MARK: - DebugStageKind

/// Stage tipizzato della debug pipeline.
public enum DebugStageKind: String, Codable, Sendable, Equatable, CaseIterable {
    case activateMode = "activate_mode"
    case gatherContext = "gather_context"
    case analyzeIssue = "analyze_issue"
    case requestReproduction = "request_reproduction"
    case reproduce
    case instrument
    case fix
    case reviewFix = "review_fix"
    case verify
    case clean
    case resolve
    case nativeStart = "native_start"
    case nativeRefresh = "native_refresh"
    case nativeSyncBreakpoints = "native_sync_breakpoints"
    case nativeSyncWatches = "native_sync_watches"
    case nativeStepIn = "native_step_in"
    case nativeStepOver = "native_step_over"
    case nativeStepOut = "native_step_out"
    case nativeStop = "native_stop"

    public var defaultPhase: DebugPipelinePhase {
        switch self {
        case .activateMode, .gatherContext, .analyzeIssue:
            return .describing
        case .requestReproduction, .reproduce:
            return .reproducing
        case .instrument:
            return .instrumenting
        case .fix, .reviewFix:
            return .fixing
        case .verify, .clean:
            return .verifying
        case .resolve:
            return .resolved
        case .nativeStart, .nativeRefresh, .nativeSyncBreakpoints,
             .nativeSyncWatches, .nativeStepIn, .nativeStepOver,
             .nativeStepOut, .nativeStop:
            return .instrumenting
        }
    }

    public var defaultExecutionStyle: TaskExecutionStyle {
        switch self {
        case .nativeStart, .nativeRefresh, .nativeSyncBreakpoints,
             .nativeSyncWatches, .nativeStepIn, .nativeStepOver,
             .nativeStepOut, .nativeStop:
            return .nativeCommand
        case .activateMode, .requestReproduction, .resolve:
            return .mcpTool
        case .gatherContext, .analyzeIssue, .reproduce,
             .instrument, .fix, .reviewFix, .verify, .clean:
            return .singleAgent
        }
    }

    public var defaultAgentRole: AgentRole? {
        switch self {
        case .reviewFix:
            return .reviewer
        case .verify:
            return .testWriter
        case .gatherContext, .analyzeIssue:
            return .explorer
        case .reproduce, .instrument, .fix, .clean:
            return .debugger
        case .activateMode, .requestReproduction, .resolve,
             .nativeStart, .nativeRefresh, .nativeSyncBreakpoints,
             .nativeSyncWatches, .nativeStepIn, .nativeStepOver,
             .nativeStepOut, .nativeStop:
            return nil
        }
    }

    public var isNativeStage: Bool {
        defaultExecutionStyle == .nativeCommand
    }
}

// MARK: - DebugPipelineSessionContext

/// Contesto tipizzato della sessione debug associata al job.
public struct DebugPipelineSessionContext: Codable, Sendable, Equatable {
    public var initialPhase: DebugPipelinePhase
    public var backendPolicy: DebugBackendPolicy
    public var errorSummary: String
    public var targetPath: String?
    public var arguments: [String]
    public var workspaceHints: [String]
    public var metadata: [String: String]

    public init(
        initialPhase: DebugPipelinePhase = .describing,
        backendPolicy: DebugBackendPolicy = .hybrid,
        errorSummary: String = "",
        targetPath: String? = nil,
        arguments: [String] = [],
        workspaceHints: [String] = [],
        metadata: [String: String] = [:]
    ) {
        self.initialPhase = initialPhase
        self.backendPolicy = backendPolicy
        self.errorSummary = errorSummary
        self.targetPath = targetPath
        self.arguments = arguments
        self.workspaceHints = workspaceHints
        self.metadata = metadata
    }

    enum CodingKeys: String, CodingKey {
        case initialPhase = "initial_phase"
        case backendPolicy = "backend_policy"
        case errorSummary = "error_summary"
        case targetPath = "target_path"
        case arguments
        case workspaceHints = "workspace_hints"
        case metadata
    }
}

extension DebugPipelineSessionContext: PipelineValidatable {
    public func validate() throws {
        if let targetPath, targetPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw PipelineValidationError.constraintViolation(
                field: "target_path",
                contract: "DebugPipelineSessionContext",
                reason: "must be omitted or non-empty"
            )
        }
    }
}
