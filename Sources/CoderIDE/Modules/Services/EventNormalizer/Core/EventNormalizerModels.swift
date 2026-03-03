import Foundation

struct TodoWritePayload {
    let id: UUID?
    let title: String
    let status: TodoStatus?
    let priority: TodoPriority?
    let notes: String?
    let activeForm: String?
    let files: [String]
}

struct DebugLogToolPayload {
    let severity: DebugEntrySeverity
    let source: String
    let message: String
    let detail: String?
    let category: String?
    let data: [String: String]
    let runId: String?
    let hypothesisId: String?
}

struct DebugHypothesizeToolPayload {
    let action: String
    let hypothesisId: UUID?
    let hypothesisIdRaw: String?
    let title: String?
    let description: String?
    let status: DebugHypothesis.HypothesisStatus?
    let evidence: String?
}

struct DebugMarkToolPayload {
    let filePath: String
    let lineNumber: Int
    let comment: String
    let originalContent: String?
}

struct DebugInstrumentToolPayload {
    let filePath: String
    let lineNumber: Int
    let type: String
    let expression: String?
    let hypothesisId: String?
    let label: String?
}

struct DebugCleanToolPayload {
    let cleanedCount: Int
    let filesCount: Int
    let detail: String?
    let status: String?
    let dryRun: Bool
}

struct DebugSessionToolPayload {
    let action: String
    let sessionId: String?
    let detail: String?
    let status: String?
}

struct DebugQueryToolPayload {
    let format: String
    let output: String?
    let detail: String?
    let status: String?
}

enum NormalizedEvent {
    case taskActivity(TaskActivity)
    case instantGrep(InstantGrepResult)
    case todoWrite(TodoWritePayload)
    case todoRead
    case planStepUpdate(stepId: String, status: PlanStepStatus, title: String?)
    case debugPhaseUpdate(phase: DebugFlowPhase, detail: String?)
    case debugUserRequest(kind: String, prompt: String)
    case debugResolved(summary: String)
    case debugLog(DebugLogToolPayload)
    case debugHypothesize(DebugHypothesizeToolPayload)
    case debugMark(DebugMarkToolPayload)
    case debugInstrument(DebugInstrumentToolPayload)
    case debugClean(DebugCleanToolPayload)
    case debugSession(DebugSessionToolPayload)
    case debugQuery(DebugQueryToolPayload)
    /// LLM requests to auto-activate plan mode panel
    case activatePlanMode(reason: String?)
    /// LLM requests to auto-activate debug mode panel
    case activateDebugMode(reason: String?)
    /// LLM requests to render a mermaid diagram in the IDE chat
    case mermaidRender(code: String, title: String?)
}

enum EventKind: String, Codable {
    case terminalSession = "terminal_session"
    case fileUpdate = "file_update"
    case instantGrep = "instant_grep"
    case todoUpdate = "todo_update"
    case planStepUpdate = "plan_step_update"
    case debugPhaseUpdate = "debug_phase_update"
    case debugUserRequest = "debug_user_request"
    case debugResolved = "debug_resolved"
    case debugToolUpdate = "debug_tool_update"
    case modeActivation = "mode_activation"
    case swarmProgress = "swarm_progress"
    case usageUpdate = "usage_update"
    case errorDiagnostic = "error_diagnostic"
    case mermaidRender = "mermaid_render"
    case generic = "generic"
}

struct NormalizedEventEnvelope {
    let version: Int
    let sourceProvider: String
    let timestamp: Date
    let kind: EventKind
    let payload: [String: String]
    let events: [NormalizedEvent]
}
