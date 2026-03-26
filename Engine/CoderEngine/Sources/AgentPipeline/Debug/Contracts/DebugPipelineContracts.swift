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
    /// Un solo turno MCP: activate_debug_mode → debug_set_phase(describing). `session_start` è lo stage DAG dedicato a `debug_session` start.
    case describePipelineBootstrap = "describe_pipeline_bootstrap"
    /// Un solo turno MCP: debug_set_phase(reproducing) → debug_request_user(reproduce).
    case reproducePipelineBootstrap = "reproduce_pipeline_bootstrap"
    /// Un solo turno MCP: debug_set_phase(fixing) → debug_snapshot capture before-fix.
    case fixPipelineBootstrap = "fix_pipeline_bootstrap"
    case activateMode = "activate_mode"
    case sessionStart = "session_start"
    case sessionExport = "session_export"
    case sessionStop = "session_stop"
    case setDescribePhase = "set_describe_phase"
    case setReproducePhase = "set_reproduce_phase"
    case setFixPhase = "set_fix_phase"
    case setVerifyPhase = "set_verify_phase"
    case gatherContext = "gather_context"
    case analyzeIssue = "analyze_issue"
    case requestClarification = "request_clarification"
    case requestReproduction = "request_reproduction"
    case reproduce
    case instrument
    case snapshot
    case hypothesize
    case fix
    case reviewFix = "review_fix"
    case verify
    case clean
    case timeline
    case resolve
    case awaitReproduceGate = "await_reproduce_gate"
    /// Solo slice `.investigation` + native: placeholder nel DAG dopo preflight UI (nessun tool MCP).
    case hostReproduceGateAck = "host_reproduce_gate_ack"
    case awaitFixGate = "await_fix_gate"
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
        case .describePipelineBootstrap, .activateMode, .sessionStart, .setDescribePhase,
             .gatherContext, .analyzeIssue, .requestClarification:
            return .describing
        case .reproducePipelineBootstrap, .setReproducePhase, .requestReproduction, .reproduce,
             .awaitReproduceGate, .hostReproduceGateAck:
            return .reproducing
        case .instrument:
            return .instrumenting
        case .fixPipelineBootstrap, .setFixPhase, .snapshot, .hypothesize, .fix, .reviewFix:
            return .fixing
        case .setVerifyPhase, .verify, .clean, .awaitFixGate, .sessionExport, .sessionStop:
            return .verifying
        case .timeline, .resolve:
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
        case .describePipelineBootstrap, .reproducePipelineBootstrap, .fixPipelineBootstrap,
             .activateMode, .sessionStart,
             .sessionExport, .sessionStop,
             .setDescribePhase, .setReproducePhase, .setFixPhase, .setVerifyPhase,
             .requestClarification, .requestReproduction,
             .resolve, .awaitReproduceGate, .hostReproduceGateAck, .awaitFixGate:
            return .mcpTool
        case .gatherContext, .analyzeIssue, .reproduce,
             .instrument, .snapshot, .hypothesize, .fix,
             .reviewFix, .verify, .clean, .timeline:
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
        case .reproduce, .instrument, .snapshot, .hypothesize,
             .fix, .clean, .timeline:
            return .debugger
        case .describePipelineBootstrap, .reproducePipelineBootstrap, .fixPipelineBootstrap,
             .activateMode, .sessionStart,
             .sessionExport, .sessionStop,
             .setDescribePhase, .setReproducePhase, .setFixPhase, .setVerifyPhase,
             .requestClarification, .requestReproduction, .resolve,
             .awaitReproduceGate, .hostReproduceGateAck, .awaitFixGate,
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
