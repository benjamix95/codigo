import Foundation
import os

// MARK: - AgentWorkerAdapterConfig

public struct AgentWorkerAdapterConfig: Sendable {
    public let streamTimeoutSec: Int
    public let maxTextLength: Int

    public init(
        streamTimeoutSec: Int = 300,
        maxTextLength: Int = 500_000
    ) {
        self.streamTimeoutSec = streamTimeoutSec
        self.maxTextLength = maxTextLength
    }
}

// MARK: - AgentWorkerDelegate

/// Delegate per ricevere eventi di streaming in tempo reale dal worker.
public protocol AgentWorkerDelegate: AnyObject, Sendable {
    func worker(
        jobId: String, taskId: String,
        didEmitTextDelta delta: String
    ) async
    func worker(
        jobId: String, taskId: String,
        didReplace replacement: String
    ) async
    func worker(
        jobId: String, taskId: String,
        didEmitRaw type: String, payload: [String: String]
    ) async
}

// MARK: - AgentWorkerAdapter

/// Adapter che esegue task della pipeline chiamando `LLMProvider.send()`.
///
/// Responsabilita':
/// - Costruire il prompt appropriato per ruolo agente e task
/// - Invocare il provider LLM e consumare lo stream
/// - Raccogliere il testo completo e restituire `WorkerTaskResult`
/// - Emettere eventi di streaming via delegate
/// - Gestire timeout e cancellation
public actor AgentWorkerAdapter {

    private static let logger = Logger(
        subsystem: "com.codigo.engine", category: "AgentWorkerAdapter"
    )

    private let provider: any LLMProvider
    private let context: WorkspaceContext
    private let jobId: String
    private let config: AgentWorkerAdapterConfig
    private let directTaskExecutor: (any PipelineDirectTaskExecutor)?
    public weak var delegate: AgentWorkerDelegate?

    public init(
        provider: any LLMProvider,
        context: WorkspaceContext,
        jobId: String,
        config: AgentWorkerAdapterConfig = AgentWorkerAdapterConfig(),
        directTaskExecutor: (any PipelineDirectTaskExecutor)? = nil
    ) {
        self.provider = provider
        self.context = context
        self.jobId = jobId
        self.config = config
        self.directTaskExecutor = directTaskExecutor
    }

    public func setDelegate(_ newDelegate: AgentWorkerDelegate?) {
        self.delegate = newDelegate
    }

    // MARK: - Execute Task

    /// Crea la closure di lavoro per il `WorkerPool.dispatch`.
    /// Restituisce un `@Sendable` closure che esegue la call LLM.
    public func makeWorkClosure(
        task: TaskNode,
        agentName: String,
        role: AgentRole
    ) -> @Sendable () async -> WorkerTaskResult {
        let provider = self.provider
        let context = self.context
        let jobId = self.jobId
        let config = self.config
        let delegate = self.delegate
        let directTaskExecutor = self.directTaskExecutor
        let taskId = task.taskId

        return {
            let startedAt = Date()
            do {
                if let directTaskExecutor,
                   let directResult = await Self.executeDirectTaskIfNeeded(
                    executor: directTaskExecutor,
                    task: task,
                    agentName: agentName,
                    role: role,
                    provider: provider,
                    context: context,
                    jobId: jobId,
                    delegate: delegate
                   )
                {
                    return directResult
                }

                let prompt = Self.buildPrompt(
                    task: task, role: role,
                    agentName: agentName, jobId: jobId
                )

                // #region agent log
                Self.debugLog("H4", "provider.send() CALLING", ["taskId": taskId, "role": role.rawValue, "providerId": provider.id, "promptLen": prompt.count, "delegateNil": delegate == nil])
                // #endregion
                let stream = try await provider.send(
                    prompt: prompt,
                    context: context,
                    attachments: nil
                )
                // #region agent log
                Self.debugLog("H4", "provider.send() RETURNED stream", ["taskId": taskId])
                // #endregion

                let fullText = try await Self.consumeStream(
                    stream: stream,
                    jobId: jobId,
                    taskId: taskId,
                    delegate: delegate,
                    config: config
                )

                let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)

                let envelope = AgentActionEnvelope(
                    agentId: "\(agentName)_\(UUID().uuidString.prefix(6))",
                    agentName: agentName,
                    agentRole: role,
                    jobId: jobId,
                    taskId: taskId,
                    actions: [AgentAction(
                        type: Self.actionType(for: role),
                        summary: String(fullText.prefix(500))
                    )],
                    confidence: fullText.isEmpty ? 0.0 : 0.8
                )

                return WorkerTaskResult(
                    taskId: taskId,
                    agentName: agentName,
                    agentRole: role,
                    success: true,
                    envelope: envelope,
                    durationMs: durationMs,
                    providerId: provider.id
                )
            } catch {
                let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
                let readable = Self.readableErrorMessage(error)
                Self.logger.error(
                    "Pipeline task \(taskId) failed after \(durationMs)ms — \(String(describing: error))"
                )
                // #region agent log
                Self.debugLog("H4H5", "task FAILED in catch", ["taskId": taskId, "error": String(describing: error), "readable": readable, "durationMs": durationMs, "errorType": String(describing: type(of: error))])
                // #endregion
                return WorkerTaskResult(
                    taskId: taskId,
                    agentName: agentName,
                    agentRole: role,
                    success: false,
                    error: readable,
                    durationMs: durationMs,
                    providerId: provider.id
                )
            }
        }
    }

    // MARK: - Stream Consumption

    private static func consumeStream(
        stream: AsyncThrowingStream<StreamEvent, Error>,
        jobId: String,
        taskId: String,
        delegate: AgentWorkerDelegate?,
        config: AgentWorkerAdapterConfig
    ) async throws -> String {
        var parts: [String] = []
        var totalLength = 0

        for try await event in stream {
            switch event {
            case .textDelta(let delta):
                if totalLength + delta.count <= config.maxTextLength {
                    parts.append(delta)
                    totalLength += delta.count
                }
                await delegate?.worker(
                    jobId: jobId, taskId: taskId,
                    didEmitTextDelta: delta
                )

            case .textReplace(let replacement):
                parts = replacement.isEmpty ? [] : [replacement]
                totalLength = replacement.count
                await delegate?.worker(
                    jobId: jobId, taskId: taskId,
                    didReplace: replacement
                )

            case .error(let message):
                throw AgentWorkerError.streamError(message)

            case .raw(let type, let payload):
                await delegate?.worker(
                    jobId: jobId, taskId: taskId,
                    didEmitRaw: type, payload: payload
                )

            case .started, .completed:
                break
            }
        }

        return parts.joined()
    }

    // MARK: - Prompt Building

    private static func buildPrompt(
        task: TaskNode,
        role: AgentRole,
        agentName: String,
        jobId: String
    ) -> String {
        let roleInstructions = roleSpecificInstructions(for: role)
        let taskInstruction = taskInstruction(for: task)
        let fileContext = task.fileScope.isEmpty
            ? ""
            : "\n\nFile scope: \(task.fileScope.joined(separator: ", "))"

        let debugInstructions = debugWorkflowInstructions(for: task, role: role)
        let markerInstructions = markerUsageInstructions(for: role)
        let workflowInstructions = planWorkflowInstructions(for: role, task: task)

        return """
        You are agent "\(agentName)" with role \(role.displayName).
        Job: \(jobId) | Task: \(task.taskId)

        ## Task
        \(taskInstruction)
        \(fileContext)

        ## Role Instructions
        \(roleInstructions)

        \(workflowInstructions)

        \(debugInstructions)

        \(markerInstructions)

        Execute the task precisely. Be concise and focused.
        When you complete this task, include a brief summary of what was done.
        If tests fail or you find critical issues, mention them explicitly.
        """
    }

    private static func taskInstruction(for task: TaskNode) -> String {
        if let fullPrompt = task.metadata["pipeline_full_prompt"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !fullPrompt.isEmpty {
            return fullPrompt
        }
        if let reviewDescription = task.metadata["review_description"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !reviewDescription.isEmpty {
            let severity = task.metadata["review_severity"]?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "warning"
            return """
            Review finding cluster: \(reviewDescription)
            Severity: \(severity)
            Fix only the issues described for the files in scope.
            """
        }
        return task.title
    }

    private static func roleSpecificInstructions(
        for role: AgentRole
    ) -> String {
        switch role {
        case .planner:
            return "Analyze the request and produce a structured execution plan."
        case .explorer:
            return """
            Explore the codebase to gather context needed for the task.
            Identify relevant files, dependencies, and patterns.
            Report your findings so the next agent (Coder) can proceed.
            """
        case .coder:
            return """
            Implement the changes as described. Write clean, minimal code.
            After making changes, update the todo status to reflect progress.
            Use [CODERIDE:todo_write|...] markers to report completion.
            """
        case .debugger:
            return "Investigate and fix the issue. Explain root cause briefly."
        case .reviewer:
            return """
            Review the code changes. Report findings as structured feedback.
            If you find critical issues, include "critical" in your summary.
            If all looks good, confirm the code is ready for testing.
            """
        case .testWriter:
            return """
            Write tests covering the changed functionality.
            Run the tests and report results.
            If tests fail, include "tests fail" in your summary.
            """
        case .docWriter:
            return """
            Update documentation to reflect the changes made.
            Include "documentation needed" in your summary if docs are required.
            """
        case .securityAuditor:
            return """
            Audit code for security vulnerabilities. Report findings.
            If you find critical vulnerabilities, include "security vulnerability" in your summary.
            """
        }
    }

    private static func markerUsageInstructions(for role: AgentRole) -> String {
        guard role == .coder || role == .debugger else { return "" }

        return """
        ## CoderIDE Markers
        You can emit these markers in your output to interact with the IDE:
        - [CODERIDE:todo_write|title=<title>|status=<done/in_progress/pending>] — Update a todo item
        - [CODERIDE:plan_step|title=<title>|status=<done/in_progress>] — Update plan step status
        - [CODERIDE:show_task_panel] — Show the task activity panel
        """
    }

    private static func planWorkflowInstructions(
        for role: AgentRole,
        task: TaskNode
    ) -> String {
        guard role == .coder || role == .explorer else { return "" }

        return """
        ## Pipeline Workflow
        This task is part of a plan build pipeline. Your work feeds into the next stage:
        Explorer -> Coder -> Reviewer -> TestWriter -> DocWriter
        Current task: "\(task.title)"
        Stay focused on this specific task only. Do not attempt to complete other tasks.
        """
    }

    private static func debugWorkflowInstructions(
        for task: TaskNode,
        role: AgentRole
    ) -> String {
        guard let debugStage = task.debugStage else { return "" }

        var lines: [String] = [
            "## Debug Pipeline Stage",
            "This task belongs to the debug pipeline.",
            "Stage: \(debugStage.rawValue)",
            "Execution style: \(task.executionStyle.rawValue)",
        ]

        if let phase = task.metadata["debug_phase"], !phase.isEmpty {
            lines.append("Target phase: \(phase)")
        }
        if let errorSummary = task.metadata["error_summary"], !errorSummary.isEmpty {
            lines.append("Error summary: \(errorSummary)")
        }
        if let backendPolicy = task.metadata["backend_policy"], !backendPolicy.isEmpty {
            lines.append("Backend policy: \(backendPolicy)")
        }
        if let tool = task.metadata["mcp_tool"] ?? task.metadata["debug_tool"], !tool.isEmpty {
            lines.append("Preferred tool for this stage: \(tool)")
        }
        if let targetPath = task.metadata["target_path"], !targetPath.isEmpty {
            lines.append("Target path: \(targetPath)")
        }

        switch debugStage {
        case .activateMode:
            lines.append("Activate debug mode and establish the debug session context.")
        case .gatherContext:
            lines.append("Collect the minimum context needed to understand the failure.")
        case .analyzeIssue:
            lines.append("Form hypotheses and identify the likeliest root cause.")
        case .requestReproduction:
            lines.append("Ask the user only for the reproduction details needed to continue.")
        case .reproduce:
            lines.append("Reproduce the issue and capture concrete evidence.")
        case .instrument:
            lines.append("Add temporary instrumentation or markers only when they help prove a hypothesis.")
        case .fix:
            lines.append("Apply the smallest safe fix that addresses the validated cause.")
        case .reviewFix:
            lines.append("Review the proposed fix critically and call out any blocking findings.")
        case .verify:
            lines.append("Run verification steps or tests and state clearly whether the fix holds.")
        case .clean:
            lines.append("Remove temporary debug markers and instrumentation after verification.")
        case .resolve:
            lines.append("Resolve the debug session with a concise summary of the outcome.")
        case .nativeStart, .nativeRefresh, .nativeSyncBreakpoints, .nativeSyncWatches,
             .nativeStepIn, .nativeStepOver, .nativeStepOut, .nativeStop:
            lines.append("Coordinate the native debugging stage and emit state updates for the IDE.")
        }

        if role == .reviewer {
            lines.append("If you find blocking issues, say so explicitly in the summary.")
        }
        if role == .testWriter {
            lines.append("If verification fails, include that tests fail or reproduction still occurs.")
        }

        return lines.joined(separator: "\n")
    }

    private static func actionType(for role: AgentRole) -> ActionType {
        switch role {
        case .coder, .debugger: return .patchProposal
        case .testWriter: return .testUpdate
        case .docWriter: return .docUpdate
        default: return .analysisNote
        }
    }

    private static func readableErrorMessage(_ error: Error) -> String {
        let description = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !description.isEmpty,
           !description.hasPrefix("The operation couldn’t be completed. (CoderEngine.AgentWorkerError") {
            return description
        }

        if let workerError = error as? AgentWorkerError,
           let workerDescription = workerError.errorDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
           !workerDescription.isEmpty {
            return workerDescription
        }

        return String(describing: error)
    }
}

// MARK: - AgentWorkerError

public enum AgentWorkerError: Error, Sendable {
    case streamError(String)
    case timeout(taskId: String, elapsedMs: Int)
}

extension AgentWorkerError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .streamError(let message):
            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Il provider ha terminato lo stream senza dettagli di errore." : trimmed
        case .timeout(let taskId, let elapsedMs):
            return "Timeout del worker pipeline per \(taskId) dopo \(elapsedMs)ms."
        }
    }
}

// #region agent log
extension AgentWorkerAdapter {
    static func debugLog(_ hypothesis: String, _ message: String, _ data: [String: Any] = [:]) {
        let path = NSHomeDirectory() + "/codigo/.cursor/debug-7f5345.log"
        let ts = Int(Date().timeIntervalSince1970 * 1000)
        var payload: [String: Any] = [
            "sessionId": "7f5345", "hypothesisId": hypothesis,
            "location": "AgentWorkerAdapter", "message": message,
            "timestamp": ts
        ]
        if !data.isEmpty { payload["data"] = data }
        if let json = try? JSONSerialization.data(withJSONObject: payload),
           let line = String(data: json, encoding: .utf8) {
            let handle = FileHandle(forWritingAtPath: path)
                ?? { FileManager.default.createFile(atPath: path, contents: nil); return FileHandle(forWritingAtPath: path)! }()
            handle.seekToEndOfFile()
            handle.write((line + "\n").data(using: .utf8)!)
            handle.closeFile()
        }
    }
}
// #endregion
