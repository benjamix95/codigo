import Foundation

extension ToolEnabledLLMProvider {
    /// The subagent runs to completion using its own ToolEnabledLLMProvider instance,
    /// then returns the result as tool output events.
    /// When `preAssignedIdentity` is provided, the caller already selected the
    /// stable swarm/card identity that must be reused for all subagent events.
    /// `onLiveEvent` is called for every intermediate event during execution, enabling
    /// real-time streaming of subagent activity to the UI (card subtitle updates, etc.).
    func executeSubagentTool(
        toolName: String,
        marker: CoderIDEMarker,
        context: WorkspaceContext,
        preAssignedIdentity: SubagentExecutionIdentity? = nil,
        onLiveEvent: (@Sendable (StreamEvent) -> Void)? = nil
    ) async -> [StreamEvent] {
        guard let role = SubagentRole.fromToolName(toolName) else {
            return [.raw(type: "tool_validation_error", payload: [
                "id": marker.payload["id"] ?? UUID().uuidString,
                "name": toolName,
                "title": "Unknown subagent",
                "detail": "No subagent role for '\(toolName)'",
                "status": "failed",
                "error_code": "unknown_subagent"
            ])]
        }

        let task = marker.payload["task"] ?? marker.payload["prompt"] ?? ""
        guard !task.isEmpty else {
            return [.raw(type: "tool_validation_error", payload: [
                "id": marker.payload["id"] ?? UUID().uuidString,
                "name": toolName,
                "title": "Missing task",
                "detail": "subagent_* tools require a 'task' argument describing what the subagent should do.",
                "status": "failed",
                "error_code": "missing_argument"
            ])]
        }

        return await SubagentExecutionLimiter.shared.withPermit {
            await executeSubagentToolWithAcquiredSlot(
                toolName: toolName,
                role: role,
                task: task,
                marker: marker,
                context: context,
                preAssignedIdentity: preAssignedIdentity,
                onLiveEvent: onLiveEvent
            )
        }
    }

    private func executeSubagentToolWithAcquiredSlot(
        toolName: String,
        role: SubagentRole,
        task: String,
        marker: CoderIDEMarker,
        context: WorkspaceContext,
        preAssignedIdentity: SubagentExecutionIdentity?,
        onLiveEvent: (@Sendable (StreamEvent) -> Void)?
    ) async -> [StreamEvent] {
        let identity = preAssignedIdentity ?? SubagentExecutionIdentityBuilder.make(role: role, task: task)
        let subagentId = identity.swarmId
        let toolCallId = marker.payload["id"] ?? UUID().uuidString
        var events: [StreamEvent] = []
        let subagentBase = subagentProviderFactory?() ?? base
        let conversationId = Self.conversationScope(from: marker.payload)
        let liveContext = SubagentLiveEventContext(
            role: role,
            toolName: toolName,
            toolCallId: toolCallId,
            subagentId: subagentId,
            agentName: identity.agentName,
            readableName: identity.readableName,
            taskSummary: identity.taskSummary,
            backendProviderId: subagentBase.id,
            backendDisplayName: subagentBase.displayName,
            conversationId: conversationId
        )
        let hasLiveCallback = onLiveEvent != nil
        let launchingDetail = "starting backend • \(liveContext.backendDisplayName)"
        let liveState = SubagentLiveState(
            initialStage: .launchingBackend,
            initialDetail: launchingDetail
        )
        let eventRecorder = SubagentEventRecorder()

        let emitLiveOnly: @Sendable (StreamEvent) -> Void = { event in
            if case .raw(let type, let payload) = event {
                SubagentPipelineLogger.log(
                    "emit_live type=\(type) swarm=\(payload["swarm_id"] ?? subagentId) stage=\(payload["subagent_stage"] ?? "-") detail=\(payload["detail"] ?? "-")"
                )
            }
            onLiveEvent?(event)
        }

        func storeEvent(_ event: StreamEvent, emitLive: Bool = false) async {
            await eventRecorder.append(event)
            guard emitLive else { return }
            emitLiveOnly(event)
        }

        await storeEvent(
            .raw(type: "agent", payload: liveContext.agentPayload(
                title: "Starting backend",
                detail: launchingDetail,
                status: "started",
                stage: .launchingBackend,
                health: .starting,
                phase: "planning",
                liveEmitted: hasLiveCallback
            )),
            emitLive: hasLiveCallback
        )

        let startDate = Date()

        do {
            // Build runtime: for explorer, restrict to read-only policy
            let subagentRuntime = UnifiedToolRuntime(
                executionController: nil,
                executionScope: .swarm
            )

            let subagentPolicy: ToolRuntimePolicy = role.canEditFiles ? policy : ToolRuntimePolicy(
                sandboxMode: "workspace-read",
                askForApproval: policy.askForApproval,
                timeoutMs: policy.timeoutMs,
                maxToolCallsPerRound: policy.maxToolCallsPerRound,
                maxRepeatedSameToolPerRound: policy.maxRepeatedSameToolPerRound,
                maxBashOutputBytes: policy.maxBashOutputBytes,
                maxReadBytesPerFile: policy.maxReadBytesPerFile,
                allowDangerousShellPatterns: false,
                allowMutatingTools: false,
                enableMCP: policy.enableMCP,
                enforceMCPEditOnly: policy.enforceMCPEditOnly,
                mcpPerCallTimeoutMs: policy.mcpPerCallTimeoutMs,
                mcpSessionIdleTTLSeconds: policy.mcpSessionIdleTTLSeconds
            )
            let subagentProvider = ToolEnabledLLMProvider(
                base: subagentBase,
                runtime: subagentRuntime,
                policy: subagentPolicy,
                executionScope: .swarm,
                maxToolRounds: role.maxToolRounds,
                subagentProviderFactory: nil  // no nested subagents
            )

            // Build the subagent prompt
            let prompt = SubagentPromptBuilder.build(role: role, task: task)
            let output = try await collectSubagentStreamOutput(
                provider: subagentProvider,
                prompt: prompt,
                role: role,
                context: context,
                liveContext: liveContext,
                liveState: liveState,
                hasLiveCallback: hasLiveCallback,
                eventRecorder: eventRecorder,
                emitLiveOnly: emitLiveOnly
            )

            await liveState.finish(
                stage: .completed,
                detail: "completed • \(liveContext.backendDisplayName)"
            )
            let durationMs = Int(Date().timeIntervalSince(startDate) * 1000)

            // Emit completed event
            await storeEvent(
                .raw(type: "agent", payload: liveContext.agentPayload(
                    title: "Completed",
                    detail: "completed • \(liveContext.backendDisplayName)",
                    status: "completed",
                    stage: .completed,
                    health: .completed,
                    phase: "executing",
                    liveEmitted: hasLiveCallback,
                    extra: [
                        "duration_ms": "\(durationMs)",
                    ]
                )),
                emitLive: hasLiveCallback
            )

            // Return result as a tool result event so the main agent gets the output
            await storeEvent(
                .raw(type: "tool_result", payload: liveContext.agentPayload(
                    title: "\(identity.agentName) completed",
                    detail: "\(identity.agentName) completed in \(durationMs)ms",
                    status: "completed",
                    stage: .completed,
                    health: .completed,
                    phase: "executing",
                    liveEmitted: hasLiveCallback,
                    extra: [
                        "id": toolCallId,
                        "name": toolName,
                        "output": output,
                        "subagent_id": subagentId,
                        "duration_ms": "\(durationMs)",
                    ]
                )),
                emitLive: hasLiveCallback
            )

        } catch {
            await liveState.finish(stage: .failed, detail: error.localizedDescription)
            let durationMs = Int(Date().timeIntervalSince(startDate) * 1000)

            await storeEvent(
                .raw(type: "agent", payload: liveContext.agentPayload(
                    title: "Failed",
                    detail: error.localizedDescription,
                    status: "failed",
                    stage: .failed,
                    health: .failed,
                    phase: "executing",
                    liveEmitted: hasLiveCallback,
                    extra: [
                        "duration_ms": "\(durationMs)",
                    ]
                )),
                emitLive: hasLiveCallback
            )

            await storeEvent(
                .raw(type: "tool_result", payload: liveContext.agentPayload(
                    title: "\(identity.agentName) failed",
                    detail: error.localizedDescription,
                    status: "failed",
                    stage: .failed,
                    health: .failed,
                    phase: "executing",
                    liveEmitted: hasLiveCallback,
                    extra: [
                        "id": toolCallId,
                        "name": toolName,
                        "output": "Subagent \(identity.agentName) failed: \(error.localizedDescription)",
                        "subagent_id": subagentId,
                        "duration_ms": "\(durationMs)",
                    ]
                )),
                emitLive: hasLiveCallback
            )
        }

        events = await eventRecorder.snapshot()
        return events
    }

    // MARK: - Skill Execution

}
