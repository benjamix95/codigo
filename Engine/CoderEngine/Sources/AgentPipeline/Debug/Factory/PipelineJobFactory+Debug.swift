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

extension PipelineJobFactory {
    // MARK: - Debug Session

    public static func fromDebugSession(
        _ request: DebugSessionRequest,
        workspace: String,
        providerId: String,
        slice: DebugPipelineSlice = .full,
        mode: PipelineMode = .strict,
        maxConcurrentWorkers: Int = 1,
        jobTimeoutMs: Int = 1_200_000
    ) -> (job: PipelineJob, tasks: [TaskNode]) {
        let jobId = "debug_\(UUID().uuidString.prefix(8))"
        let normalizedError = request.errorSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let jobRequest = normalizedError.isEmpty
            ? "Debug session pipeline"
            : "Debug: \(String(normalizedError.prefix(160)))"

        let debugSession = DebugPipelineSessionContext(
            initialPhase: .describing,
            backendPolicy: request.backendPolicy,
            errorSummary: normalizedError,
            targetPath: request.targetPath,
            arguments: request.arguments,
            workspaceHints: request.workspaceHints,
            metadata: [
                "include_review_stage": request.includeReviewStage ? "true" : "false",
                "include_cleanup_stage": request.includeCleanupStage ? "true" : "false",
                "include_native_stages": request.includeNativeStages ? "true" : "false",
                "pipeline_slice": slice.rawValue,
            ]
        )

        let job = PipelineJob(
            jobId: jobId,
            workspace: workspace,
            request: jobRequest,
            jobKind: .debug,
            mode: mode,
            selectedProviderProfile: providerId,
            debugSession: debugSession,
            jobTimeoutMs: jobTimeoutMs,
            maxConcurrentWorkers: maxConcurrentWorkers
        )

        var tasks: [TaskNode] = []
        var previousTaskId: String?

        func shouldInclude(_ stage: DebugStageKind) -> Bool {
            switch slice {
            case .full:
                return true
            case .intake:
                switch stage {
                case .activateMode, .gatherContext, .analyzeIssue, .requestReproduction,
                     .awaitReproduceGate:
                    return true
                default:
                    return false
                }
            case .investigation:
                switch stage {
                case .nativeStart, .nativeSyncBreakpoints, .nativeSyncWatches,
                     .reproduce, .instrument, .fix, .reviewFix, .verify,
                     .awaitFixGate:
                    return true
                default:
                    return false
                }
            case .resolution:
                switch stage {
                case .clean, .nativeStop, .resolve:
                    return true
                default:
                    return false
                }
            }
        }

        func appendStage(
            _ stage: DebugStageKind,
            title: String,
            taskType: TaskType,
            priority: Int,
            fileScope: [String] = request.workspaceHints,
            symbolScope: [String] = [],
            metadata: [String: String] = [:]
        ) {
            guard shouldInclude(stage) else { return }
            let taskId = "task_\(tasks.count)_\(sanitizeDebugId(title))"
            var mergedMetadata = debugBaseMetadata(
                stage: stage,
                request: request,
                metadata: metadata
            )
            mergedMetadata["job_id"] = jobId

            var task = TaskNode(
                taskId: taskId,
                title: title,
                dependsOn: previousTaskId.map { [$0] } ?? [],
                priority: priority,
                risk: riskForDebugStage(stage),
                taskType: taskType,
                executionStyle: stage.defaultExecutionStyle,
                preferredAgentRole: preferredRoleForDebugStage(stage),
                debugStage: stage,
                fileScope: fileScope,
                symbolScope: symbolScope,
                metadata: mergedMetadata,
                status: .pending,
                timeoutMs: timeoutForDebugStage(stage)
            )
            task.deriveTaskLabel()
            tasks.append(task)
            previousTaskId = taskId
        }

        appendStage(
            .activateMode,
            title: "Activate Debug Mode",
            taskType: .bugfix,
            priority: 100,
            metadata: ["mcp_tool": "activate_debug_mode"]
        )
        appendStage(
            .gatherContext,
            title: "Gather Debug Context",
            taskType: .bugfix,
            priority: 96,
            metadata: ["debug_tool": "debug_context"]
        )
        appendStage(
            .analyzeIssue,
            title: "Analyze Issue",
            taskType: .bugfix,
            priority: 92,
            metadata: ["debug_tool": "debug_trace_analyze"]
        )
        appendStage(
            .requestReproduction,
            title: "Request Reproduction",
            taskType: .bugfix,
            priority: 88,
            metadata: ["mcp_tool": "debug_request_user"]
        )
        appendStage(
            .awaitReproduceGate,
            title: "Await Reproduce Confirmation",
            taskType: .bugfix,
            priority: 87,
            metadata: ["mcp_tool": "debug_request_user", "gate_kind": "reproduce", "user_gate": "true"]
        )

        if request.includeNativeStages {
            appendStage(
                .nativeStart,
                title: "Start Native Debug Session",
                taskType: .bugfix,
                priority: 84
            )
            appendStage(
                .nativeSyncBreakpoints,
                title: "Sync Native Breakpoints",
                taskType: .bugfix,
                priority: 82
            )
            appendStage(
                .nativeSyncWatches,
                title: "Sync Native Watches",
                taskType: .bugfix,
                priority: 80
            )
        }

        appendStage(
            .reproduce,
            title: "Reproduce Bug",
            taskType: .bugfix,
            priority: 76
        )
        appendStage(
            .instrument,
            title: "Instrument Runtime",
            taskType: .refactor,
            priority: 72,
            metadata: ["debug_tool": "debug_instrument"]
        )
        appendStage(
            .fix,
            title: "Apply Fix",
            taskType: .bugfix,
            priority: 68
        )

        if request.includeReviewStage {
            appendStage(
                .reviewFix,
                title: "Review Fix",
                taskType: .refactor,
                priority: 64
            )
        }

        appendStage(
            .verify,
            title: "Verify Fix",
            taskType: .test,
            priority: 60,
            metadata: ["debug_tool": "debug_test_check"]
        )

        appendStage(
            .awaitFixGate,
            title: "Await Fix Confirmation",
            taskType: .bugfix,
            priority: 57,
            metadata: ["mcp_tool": "debug_request_user", "gate_kind": "fix_confirmation", "user_gate": "true"]
        )

        if request.includeCleanupStage {
            appendStage(
                .clean,
                title: "Clean Debug Artifacts",
                taskType: .refactor,
                priority: 56,
                metadata: ["debug_tool": "debug_clean"]
            )
        }

        if request.includeNativeStages {
            appendStage(
                .nativeStop,
                title: "Stop Native Debug Session",
                taskType: .bugfix,
                priority: 52
            )
        }

        appendStage(
            .resolve,
            title: "Resolve Debug Session",
            taskType: .bugfix,
            priority: 48,
            metadata: ["mcp_tool": "debug_resolve"]
        )

        return (job, tasks)
    }
}
