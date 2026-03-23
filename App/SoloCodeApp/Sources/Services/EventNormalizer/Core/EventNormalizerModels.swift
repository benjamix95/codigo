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
    let confidence: Int?
    let rootCauseType: String?
    let relatedFiles: [String]
    let relatedTests: [String]
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
    let workspacePath: String?
    let detail: String?
    let output: String?
    let status: String?
}

struct DebugNativeSessionToolPayload {
    let action: String
    let detail: String?
    let state: NativeDebugSessionState
    let breakpoints: [DebugBreakpoint]
    let arguments: [String]
    let watchExpressions: [String]
}

struct DebugQueryToolPayload {
    let format: String
    let output: String?
    let detail: String?
    let status: String?
}

struct DebugTraceAnalyzeToolPayload {
    let errorType: String?
    let detail: String?
    let output: String?
}

struct DebugSnapshotToolPayload {
    let action: String
    let label: String?
    let compareWith: String?
    let detail: String?
    let output: String?
}

struct DebugTimelineToolPayload {
    let format: String
    let detail: String?
    let output: String?
}

struct DebugTestCheckToolPayload {
    let scope: String
    let detail: String?
    let output: String?
    let status: String?
    let overallStatus: String?
    let passed: Int
    let failed: Int
    let schemes: String?
}

struct PlanStepUpsertPayload {
    let stepId: String
    let status: PlanStepStatus
    let title: String?
    let description: String?
    let targetFile: String?
    let linkedFiles: [String]
    let dependsOn: [String]
    let notes: String?
    let conversationId: String?
}

struct PlanStepBatchUpdateItemPayload {
    let stepId: String
    let status: PlanStepStatus
    let title: String?
    let description: String?
    let targetFile: String?
    let linkedFiles: [String]
    let dependsOn: [String]
    let notes: String?
}

struct PlanRequestUserInputPayload {
    let questionnaire: PlanClarificationQuestionnaire
    let title: String?
    let phase: String?
    let round: Int?
    let context: String?
    let conversationId: String?
}

enum NormalizedEvent {
    case taskActivity(TaskActivity)
    case instantGrep(InstantGrepResult)
    case todoWrite(TodoWritePayload)
    case todoRead
    case planStepUpdate(stepId: String, status: PlanStepStatus, title: String?)
    case planCreate(goal: String, chosenPath: String?, steps: [PlanStepUpsertPayload], conversationId: String?)
    case planRead(conversationId: String?)
    case planStepUpsert(PlanStepUpsertPayload)
    case planStepBatchUpdate(items: [PlanStepBatchUpdateItemPayload], conversationId: String?)
    case planStepReorder(orderedStepIds: [String], conversationId: String?)
    case planStepDependencySet(stepId: String, dependsOn: [String], conversationId: String?)
    case planSetWalkthrough(markdown: String, summary: String?, outcome: String, conversationId: String?)
    case planHistoryRead(conversationId: String?, limit: Int?)
    case planDiff(fromSnapshotId: String, toSnapshotId: String?, conversationId: String?)
    case planRequestUserInput(PlanRequestUserInputPayload)
    case debugPhaseUpdate(phase: DebugFlowPhase, detail: String?)
    case debugUserRequest(kind: String, prompt: String)
    case debugResolved(summary: String)
    case debugLog(DebugLogToolPayload)
    case debugHypothesize(DebugHypothesizeToolPayload)
    case debugMark(DebugMarkToolPayload)
    case debugInstrument(DebugInstrumentToolPayload)
    case debugClean(DebugCleanToolPayload)
    case debugSession(DebugSessionToolPayload)
    case debugNativeSession(DebugNativeSessionToolPayload)
    case debugQuery(DebugQueryToolPayload)
    case debugTraceAnalyze(DebugTraceAnalyzeToolPayload)
    case debugSnapshot(DebugSnapshotToolPayload)
    case debugTimeline(DebugTimelineToolPayload)
    case debugTestCheck(DebugTestCheckToolPayload)
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
    case planLifecycle = "plan_lifecycle"
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
