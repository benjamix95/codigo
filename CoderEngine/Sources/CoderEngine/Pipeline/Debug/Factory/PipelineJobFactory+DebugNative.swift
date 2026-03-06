import Foundation

extension PipelineJobFactory {
    public static func fromDebugNativeStage(
        _ request: DebugSessionRequest,
        stage: DebugStageKind,
        workspace: String,
        providerId: String,
        mode: PipelineMode = .strict,
        maxConcurrentWorkers: Int = 1,
        jobTimeoutMs: Int = 120_000
    ) -> (job: PipelineJob, tasks: [TaskNode]) {
        precondition(stage.isNativeStage, "fromDebugNativeStage requires a native debug stage")

        let jobId = "debug_native_\(UUID().uuidString.prefix(8))"
        let normalizedError = request.errorSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let titlePrefix = normalizedError.isEmpty ? "Debug native stage" : "Debug: \(normalizedError)"

        let job = PipelineJob(
            jobId: jobId,
            workspace: workspace,
            request: "\(titlePrefix) • \(stage.rawValue)",
            jobKind: .debug,
            mode: mode,
            selectedProviderProfile: providerId,
            debugSession: DebugPipelineSessionContext(
                initialPhase: stage.defaultPhase,
                backendPolicy: request.backendPolicy,
                errorSummary: normalizedError,
                targetPath: request.targetPath,
                arguments: request.arguments,
                workspaceHints: request.workspaceHints,
                metadata: [
                    "include_native_stages": request.includeNativeStages ? "true" : "false",
                    "native_stage": stage.rawValue,
                ]
            ),
            jobTimeoutMs: jobTimeoutMs,
            maxConcurrentWorkers: maxConcurrentWorkers
        )

        var metadata = debugBaseMetadata(
            stage: stage,
            request: request,
            metadata: [:]
        )
        metadata["job_id"] = jobId

        var task = TaskNode(
            taskId: "task_0_\(sanitizeDebugId(stage.rawValue))",
            title: stageTitle(for: stage),
            priority: 100,
            risk: riskForDebugStage(stage),
            taskType: .bugfix,
            executionStyle: .nativeCommand,
            preferredAgentRole: preferredRoleForDebugStage(stage),
            debugStage: stage,
            fileScope: request.workspaceHints,
            metadata: metadata,
            status: .pending,
            timeoutMs: timeoutForDebugStage(stage)
        )
        task.deriveTaskLabel()
        return (job, [task])
    }

    private static func stageTitle(for stage: DebugStageKind) -> String {
        switch stage {
        case .nativeStart:
            return "Start Native Debug Session"
        case .nativeRefresh:
            return "Refresh Native Debug Session"
        case .nativeSyncBreakpoints:
            return "Sync Native Breakpoints"
        case .nativeSyncWatches:
            return "Sync Native Watches"
        case .nativeStepIn:
            return "Native Step In"
        case .nativeStepOver:
            return "Native Step Over"
        case .nativeStepOut:
            return "Native Step Out"
        case .nativeStop:
            return "Stop Native Debug Session"
        default:
            return "Execute Native Debug Stage"
        }
    }
}
