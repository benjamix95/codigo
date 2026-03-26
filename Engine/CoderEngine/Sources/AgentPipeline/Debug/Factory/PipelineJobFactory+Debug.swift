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
        maxConcurrentWorkers: Int = 5,
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

        func shouldInclude(_ stage: DebugStageKind) -> Bool {
            switch slice {
            case .full:
                return true
            case .intake:
                switch stage {
                case .describePipelineBootstrap, .gatherContext,
                     .requestClarification, .analyzeIssue, .reproducePipelineBootstrap,
                     .awaitReproduceGate:
                    return true
                default:
                    return false
                }
            case .investigation:
                switch stage {
                case .nativeStart, .nativeSyncBreakpoints, .nativeSyncWatches,
                     .reproduce, .instrument, .fixPipelineBootstrap, .snapshot,
                     .hypothesize, .fix, .reviewFix, .setVerifyPhase,
                     .verify, .awaitFixGate:
                    return true
                default:
                    return false
                }
            case .resolution:
                switch stage {
                case .clean, .nativeStop, .timeline, .sessionExport,
                     .resolve, .sessionStop:
                    return true
                default:
                    return false
                }
            }
        }

        @discardableResult
        func appendStage(
            _ stage: DebugStageKind,
            title: String,
            taskType: TaskType,
            priority: Int,
            dependsOn dependencies: [String?] = [],
            fileScope: [String] = request.workspaceHints,
            symbolScope: [String] = [],
            metadata: [String: String] = [:]
        ) -> String? {
            guard shouldInclude(stage) else { return nil }
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
                dependsOn: dependencies.compactMap { $0 },
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
            return taskId
        }

        let bootstrapPrompt = """
        In one turn, run these MCP debug setup steps in strict order. Complete each successfully before the next:
        1) Tool activate_debug_mode (or equivalent activate_debug_mode MCP).
        2) Tool debug_session with action=start.
        3) Tool debug_set_phase with phase=describing.
        Then reply with a brief summary that the session exists and is in the describing phase.
        """
        let describeBootstrapId = appendStage(
            .describePipelineBootstrap,
            title: "Open Debug Session",
            taskType: .bugfix,
            priority: 100,
            metadata: [
                "mcp_tool": "activate_debug_mode",
                "pipeline_full_prompt": bootstrapPrompt,
            ]
        )
        let gatherContextId = appendStage(
            .gatherContext,
            title: "Gather Debug Context",
            taskType: .bugfix,
            priority: 96,
            dependsOn: [describeBootstrapId],
            metadata: ["debug_tool": "debug_context"]
        )
        let describeQuestionOneId = appendStage(
            .requestClarification,
            title: "Request Describe Clarification One",
            taskType: .bugfix,
            priority: 95,
            dependsOn: [gatherContextId],
            metadata: [
                "mcp_tool": "debug_request_user",
                "request_kind": "question",
                "question_index": "1",
            ]
        )
        // Seconda domanda dopo la prima: evita due turn agente paralleli su debug_request_user.
        let describeQuestionTwoId = appendStage(
            .requestClarification,
            title: "Request Describe Clarification Two",
            taskType: .bugfix,
            priority: 94,
            dependsOn: [describeQuestionOneId].compactMap { $0 },
            metadata: [
                "mcp_tool": "debug_request_user",
                "request_kind": "question",
                "question_index": "2",
            ]
        )
        let clarifyDeps = [describeQuestionOneId, describeQuestionTwoId].compactMap { $0 }
        let analyzeIssueDeps: [String] = clarifyDeps.isEmpty
            ? [gatherContextId].compactMap { $0 }
            : clarifyDeps
        let analyzeIssueId = appendStage(
            .analyzeIssue,
            title: "Analyze Issue",
            taskType: .bugfix,
            priority: 92,
            dependsOn: analyzeIssueDeps,
            metadata: ["debug_tool": "debug_trace_analyze"]
        )
        let reproduceBootstrapPrompt = """
        In one turn, in strict order:
        1) Tool debug_set_phase with phase=reproducing.
        2) Tool debug_request_user with request_kind=reproduce (ask only what is needed to reproduce).
        Summarize briefly that the flow is in reproducing phase.
        """
        let reproduceBootstrapId = appendStage(
            .reproducePipelineBootstrap,
            title: "Enter Reproduce Phase and Request Reproduction",
            taskType: .bugfix,
            priority: 90,
            dependsOn: [analyzeIssueId],
            metadata: [
                "mcp_tool": "debug_set_phase",
                "pipeline_full_prompt": reproduceBootstrapPrompt,
            ]
        )
        let awaitReproduceGateId = appendStage(
            .awaitReproduceGate,
            title: "Await Reproduce Confirmation",
            taskType: .bugfix,
            priority: 87,
            dependsOn: [reproduceBootstrapId],
            metadata: [
                "mcp_tool": "debug_request_user",
                "gate_kind": "reproduce",
                "user_gate": "true",
            ]
        )

        var nativeSyncDeps: [String] = []
        if request.includeNativeStages {
            let nativeStartId = appendStage(
                .nativeStart,
                title: "Start Native Debug Session",
                taskType: .bugfix,
                priority: 84,
                dependsOn: [awaitReproduceGateId]
            )
            let nativeSyncBreakpointsId = appendStage(
                .nativeSyncBreakpoints,
                title: "Sync Native Breakpoints",
                taskType: .bugfix,
                priority: 82,
                dependsOn: [nativeStartId]
            )
            let nativeSyncWatchesId: String? = request.watchExpressions.isEmpty
                ? nil
                : appendStage(
                    .nativeSyncWatches,
                    title: "Sync Native Watches",
                    taskType: .bugfix,
                    priority: 80,
                    dependsOn: [nativeSyncBreakpointsId].compactMap { $0 }
                )
            nativeSyncDeps = [nativeSyncBreakpointsId, nativeSyncWatchesId].compactMap { $0 }
        }
        let reproduceDeps: [String] = nativeSyncDeps.isEmpty
            ? [awaitReproduceGateId].compactMap { $0 }
            : nativeSyncDeps

        let reproduceId = appendStage(
            .reproduce,
            title: "Reproduce Bug",
            taskType: .bugfix,
            priority: 76,
            dependsOn: reproduceDeps
        )
        let instrumentId = appendStage(
            .instrument,
            title: "Instrument Runtime",
            taskType: .refactor,
            priority: 72,
            dependsOn: [reproduceId],
            metadata: ["debug_tool": "debug_instrument"]
        )
        let fixBootstrapPrompt = """
        In one turn, in strict order:
        1) Tool debug_set_phase with phase=fixing.
        2) Tool debug_snapshot with action=capture and label=before-fix.
        Summarize briefly that fixing phase is active and the baseline snapshot is stored.
        """
        let fixPipelineBootstrapId = appendStage(
            .fixPipelineBootstrap,
            title: "Enter Fix Phase and Capture Before-Fix Snapshot",
            taskType: .bugfix,
            priority: 71,
            dependsOn: [instrumentId],
            metadata: [
                "mcp_tool": "debug_set_phase",
                "pipeline_full_prompt": fixBootstrapPrompt,
            ]
        )
        let proposeHypothesisId = appendStage(
            .hypothesize,
            title: "Propose Debug Hypothesis",
            taskType: .bugfix,
            priority: 69,
            dependsOn: [fixPipelineBootstrapId],
            metadata: ["debug_tool": "debug_hypothesize", "action": "propose"]
        )
        let fixId = appendStage(
            .fix,
            title: "Apply Fix",
            taskType: .bugfix,
            priority: 68,
            dependsOn: [proposeHypothesisId]
        )
        let afterFixSnapshotId = appendStage(
            .snapshot,
            title: "Capture After Fix Snapshot",
            taskType: .bugfix,
            priority: 67,
            dependsOn: [fixId],
            metadata: [
                "debug_tool": "debug_snapshot",
                "action": "capture",
                "label": "after-fix",
            ]
        )

        let setVerifyPhaseId = appendStage(
            .setVerifyPhase,
            title: "Set Verify Phase",
            taskType: .bugfix,
            priority: 66,
            dependsOn: [afterFixSnapshotId],
            metadata: ["mcp_tool": "debug_set_phase", "phase": "verifying"]
        )

        let reviewFixId: String?
        if request.includeReviewStage {
            reviewFixId = appendStage(
                .reviewFix,
                title: "Review Fix",
                taskType: .refactor,
                priority: 64,
                dependsOn: [afterFixSnapshotId]
            )
        } else {
            reviewFixId = nil
        }

        let verifyId = appendStage(
            .verify,
            title: "Verify Fix",
            taskType: .test,
            priority: 60,
            dependsOn: [setVerifyPhaseId],
            metadata: ["debug_tool": "debug_test_check"]
        )
        let compareSnapshotId = appendStage(
            .snapshot,
            title: "Compare Fix Snapshots",
            taskType: .bugfix,
            priority: 59,
            dependsOn: [verifyId],
            metadata: [
                "debug_tool": "debug_snapshot",
                "action": "compare",
                "label": "after-fix",
                "compare_with": "before-fix",
            ]
        )
        let updateHypothesisId = appendStage(
            .hypothesize,
            title: "Update Debug Hypothesis",
            taskType: .bugfix,
            priority: 58,
            dependsOn: [compareSnapshotId],
            metadata: ["debug_tool": "debug_hypothesize", "action": "update"]
        )

        let awaitFixGateId = appendStage(
            .awaitFixGate,
            title: "Await Fix Confirmation",
            taskType: .bugfix,
            priority: 57,
            dependsOn: [reviewFixId, updateHypothesisId],
            metadata: [
                "mcp_tool": "debug_request_user",
                "gate_kind": "fix_confirmation",
                "user_gate": "true",
            ]
        )

        let cleanId: String?
        if request.includeCleanupStage {
            cleanId = appendStage(
                .clean,
                title: "Clean Debug Artifacts",
                taskType: .refactor,
                priority: 56,
                dependsOn: [awaitFixGateId],
                metadata: ["debug_tool": "debug_clean"]
            )
        } else {
            cleanId = nil
        }

        let nativeStopId: String?
        if request.includeNativeStages {
            nativeStopId = appendStage(
                .nativeStop,
                title: "Stop Native Debug Session",
                taskType: .bugfix,
                priority: 52,
                dependsOn: [cleanId ?? awaitFixGateId]
            )
        } else {
            nativeStopId = nil
        }

        let timelineId = appendStage(
            .timeline,
            title: "Build Debug Timeline",
            taskType: .bugfix,
            priority: 50,
            dependsOn: [cleanId ?? awaitFixGateId, nativeStopId],
            metadata: ["debug_tool": "debug_timeline"]
        )
        let sessionExportId = appendStage(
            .sessionExport,
            title: "Export Debug Session",
            taskType: .bugfix,
            priority: 49,
            dependsOn: [cleanId ?? awaitFixGateId, nativeStopId],
            metadata: ["mcp_tool": "debug_session", "action": "export"]
        )
        let resolveId = appendStage(
            .resolve,
            title: "Resolve Debug Session",
            taskType: .bugfix,
            priority: 48,
            dependsOn: [timelineId, sessionExportId],
            metadata: ["mcp_tool": "debug_resolve"]
        )
        _ = appendStage(
            .sessionStop,
            title: "Stop Debug Session",
            taskType: .bugfix,
            priority: 47,
            dependsOn: [resolveId],
            metadata: ["mcp_tool": "debug_session", "action": "stop"]
        )

        return (job, tasks)
    }
}
