import CoderEngine
import Foundation

actor DebugNativePipelineExecutor: PipelineDirectTaskExecutor {
    private let adapter: DebugNativePipelineAdapter

    init(
        debugService: DebugService
    ) {
        self.adapter = DebugNativePipelineAdapter(backends: [
            DebugNativeXcodeBuildMCPBackend(),
            DebugNativeLLDBBackend(debugService: debugService),
        ])
    }

    func canExecute(task: TaskNode) async -> Bool {
        task.executionStyle == .nativeCommand
            && task.debugStage?.isNativeStage == true
    }

    func execute(
        task: TaskNode,
        agentName: String,
        role: AgentRole,
        provider: any LLMProvider,
        context _: WorkspaceContext,
        jobId: String,
        delegate: AgentWorkerDelegate?
    ) async -> WorkerTaskResult {
        let startedAt = Date()
        guard let command = DebugNativePipelineTaskContext(task: task) else {
            return WorkerTaskResult(
                taskId: task.taskId,
                agentName: agentName,
                agentRole: role,
                success: false,
                error: "Native debug context non valido.",
                durationMs: 0,
                providerId: provider.id
            )
        }

        let outcome = await adapter.execute(context: command, provider: provider)
        for log in outcome.logs {
            await emitLog(
                log,
                jobId: jobId,
                taskId: task.taskId,
                delegate: delegate
            )
        }

        guard let state = outcome.state else {
            let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
            return WorkerTaskResult(
                taskId: task.taskId,
                agentName: agentName,
                agentRole: role,
                success: false,
                error: "Nessun risultato disponibile per lo stage native.",
                durationMs: durationMs,
                providerId: provider.id
            )
        }

        await emitNativeSession(
            state: state,
            command: command,
            jobId: jobId,
            taskId: task.taskId,
            delegate: delegate
        )
        await emitOutcomeLog(
            state: state,
            command: command,
            jobId: jobId,
            taskId: task.taskId,
            delegate: delegate
        )

        let durationMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        return WorkerTaskResult(
            taskId: task.taskId,
            agentName: agentName,
            agentRole: role,
            success: state.status != .error,
            error: state.status == .error ? (state.lastError ?? "Native debug stage failed.") : nil,
            durationMs: durationMs,
            providerId: provider.id
        )
    }

    private func emitLog(
        _ log: DebugNativeBackendLog,
        jobId: String,
        taskId: String,
        delegate: AgentWorkerDelegate?
    ) async {
        await delegate?.worker(
            jobId: jobId,
            taskId: taskId,
            didEmitRaw: "debug_log",
            payload: [
                "severity": log.severity.rawValue,
                "source": log.source,
                "message": log.message,
                "detail": log.detail ?? "",
                "category": log.category ?? "native",
                "status": "completed",
                "group_id": taskId,
            ]
        )
    }

    private func emitOutcomeLog(
        state: NativeDebugSessionState,
        command: DebugNativePipelineTaskContext,
        jobId: String,
        taskId: String,
        delegate: AgentWorkerDelegate?
    ) async {
        let success = state.status != .error
        let message = success
            ? "Native stage \(command.stage.rawValue) completato."
            : "Native stage \(command.stage.rawValue) fallito."
        await emitLog(
            DebugNativeBackendLog(
                severity: success ? .info : .error,
                source: "debug_native_executor",
                message: message,
                detail: state.lastError,
                category: "native"
            ),
            jobId: jobId,
            taskId: taskId,
            delegate: delegate
        )
    }

    private func emitNativeSession(
        state: NativeDebugSessionState,
        command: DebugNativePipelineTaskContext,
        jobId: String,
        taskId: String,
        delegate: AgentWorkerDelegate?
    ) async {
        var payload: [String: String] = [
            "action": command.stage.rawValue,
            "status": state.status.rawValue,
            "adapter": state.adapter,
            "breakpoints_count": "\(state.breakpointsCount)",
            "group_id": taskId,
        ]
        payload["target_path"] = state.targetPath ?? command.targetPath ?? ""
        payload["last_command"] = state.lastCommand ?? command.stage.rawValue
        payload["last_error"] = state.lastError ?? ""
        payload["detail"] = nativeDetail(for: state, stage: command.stage)
        payload["arguments_json"] = encodeJSON(command.arguments)
        payload["watch_expressions_json"] = encodeJSON(command.watchExpressions)
        payload["native_breakpoints_json"] = encodeJSON(command.breakpoints)
        payload["call_stack_json"] = encodeJSON(state.callStack)
        payload["watch_variables_json"] = encodeJSON(state.watchVariables)

        await delegate?.worker(
            jobId: jobId,
            taskId: taskId,
            didEmitRaw: "debug_native_session",
            payload: payload
        )
    }

    private func nativeDetail(
        for state: NativeDebugSessionState,
        stage: DebugStageKind
    ) -> String {
        if let lastError = state.lastError, !lastError.isEmpty {
            return lastError
        }
        switch stage {
        case .nativeStart:
            return "Native debug session started."
        case .nativeRefresh:
            return "Native debug session refreshed."
        case .nativeSyncBreakpoints:
            return "Native breakpoints synchronized."
        case .nativeSyncWatches:
            return "Native watches synchronized."
        case .nativeStepIn:
            return "Native step in executed."
        case .nativeStepOver:
            return "Native step over executed."
        case .nativeStepOut:
            return "Native step out executed."
        case .nativeStop:
            return "Native debug session stopped."
        default:
            return "Native debug stage completed."
        }
    }

    private func encodeJSON<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(value),
              let json = String(data: data, encoding: .utf8) else {
            return ""
        }
        return json
    }
}
