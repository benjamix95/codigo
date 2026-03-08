import Foundation

extension ToolEnabledLLMProvider {
    func collectSubagentStreamOutput(
        provider subagentProvider: ToolEnabledLLMProvider,
        prompt: String,
        role: SubagentRole,
        context: WorkspaceContext,
        liveContext: SubagentLiveEventContext,
        liveState: SubagentLiveState,
        hasLiveCallback: Bool,
        eventRecorder: SubagentEventRecorder,
        emitLiveOnly: @escaping @Sendable (StreamEvent) -> Void
    ) async throws -> String {
        var fullTextParts: [String] = []
        var fullTextLength = 0
        var liveTextBuffer = ""
        var lastLiveEmitAt = Date.distantPast

        func storeEvent(_ event: StreamEvent, emitLive: Bool = false) async {
            await eventRecorder.append(event)
            guard emitLive else { return }
            emitLiveOnly(event)
        }

        func emitBufferedLiveTextIfNeeded(force: Bool = false) async {
            guard hasLiveCallback else { return }
            guard !liveTextBuffer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                liveTextBuffer = ""
                return
            }
            let now = Date()
            let shouldEmit =
                force
                || liveTextBuffer.count >= 1200
                || now.timeIntervalSince(lastLiveEmitAt) >= 0.20
            guard shouldEmit else { return }
            let chunk = String(liveTextBuffer.prefix(1200))
            let detail = Self.latestMeaningfulLine(in: chunk)
            let event = StreamEvent.raw(type: "subagent_text", payload: liveContext.textPayload(
                title: "Live output",
                detail: detail,
                text: chunk,
                source: "assistant",
                liveEmitted: hasLiveCallback
            ))
            await storeEvent(event, emitLive: hasLiveCallback)
            liveTextBuffer = ""
            lastLiveEmitAt = now
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                await liveState.update(
                    stage: .waitingFirstEvent,
                    detail: "waiting for first event • \(liveContext.backendDisplayName)"
                )
                defer {
                    Task {
                        await emitBufferedLiveTextIfNeeded(force: true)
                    }
                }
                let stream = try await subagentProvider.send(
                    prompt: prompt,
                    context: context,
                    imageURLs: nil
                )
                for try await event in stream {
                    try Task.checkCancellation()
                    switch event {
                    case .textDelta(let delta):
                        if fullTextLength + delta.count <= 50_000 {
                            fullTextParts.append(delta)
                            fullTextLength += delta.count
                        }
                        if hasLiveCallback,
                           !delta.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty {
                            let wasFirst = await liveState.recordMeaningfulEvent(
                                stage: .streamingOutput,
                                detail: "receiving live output • \(liveContext.backendDisplayName)"
                            )
                            if wasFirst {
                                await storeEvent(
                                    .raw(type: "agent", payload: liveContext.agentPayload(
                                        title: "Receiving live output",
                                        detail: "receiving live output • \(liveContext.backendDisplayName)",
                                        status: "running",
                                        stage: .streamingOutput,
                                        health: .active,
                                        phase: "executing",
                                        liveEmitted: true
                                    )),
                                    emitLive: true
                                )
                            }
                            liveTextBuffer += delta
                                if liveTextBuffer.count > 2400 {
                                    liveTextBuffer = String(liveTextBuffer.suffix(2400))
                                }
                                await emitBufferedLiveTextIfNeeded()
                        }
                    case .raw(let type, var payload):
                        await emitBufferedLiveTextIfNeeded(force: true)
                        let stage = Self.stageForSubagentEvent(type: type, payload: payload)
                        let detail = Self.detailForSubagentEvent(type: type, payload: payload)
                        let wasFirst = await liveState.recordMeaningfulEvent(
                            stage: stage,
                            detail: detail
                        )
                        if wasFirst {
                            await storeEvent(
                                .raw(type: "agent", payload: liveContext.agentPayload(
                                    title: "Live event received",
                                    detail: detail,
                                    status: "running",
                                    stage: stage,
                                    health: .active,
                                    phase: Self.phaseForSubagentEvent(type: type, payload: payload),
                                    liveEmitted: true
                                )),
                                emitLive: true
                            )
                        }
                        payload = liveContext.enrichRawPayload(
                            payload,
                            stage: stage,
                            phase: Self.phaseForSubagentEvent(type: type, payload: payload),
                            liveEmitted: hasLiveCallback
                        )
                        let enriched = StreamEvent.raw(type: type, payload: payload)
                        await storeEvent(enriched, emitLive: hasLiveCallback)
                    default:
                        break
                    }
                }
            }

            group.addTask {
                guard hasLiveCallback else { return }
                while true {
                    try await Task.sleep(
                        nanoseconds: UInt64(
                            SubagentExecutionRuntimeSettings.waitingHeartbeatIntervalSeconds * 1_000_000_000
                        )
                    )
                    let snapshot = await liveState.snapshot()
                    if snapshot.finished {
                        return
                    }
                    let now = Date()
                    let elapsed = Int(now.timeIntervalSince(snapshot.startedAt))
                    if !snapshot.hasMeaningfulEvent {
                        if now.timeIntervalSince(snapshot.startedAt) >= SubagentExecutionRuntimeSettings.firstMeaningfulEventDeadlineSeconds {
                            throw SubagentNoMeaningfulEventError(
                                roleName: role.displayName,
                                backendName: liveContext.backendDisplayName,
                                timeoutSeconds: Int(SubagentExecutionRuntimeSettings.firstMeaningfulEventDeadlineSeconds)
                            )
                        }
                        let detail = "waiting for first event • \(liveContext.backendDisplayName) • \(elapsed)s"
                        await liveState.markHeartbeat(detail: detail)
                        emitLiveOnly(
                            .raw(type: "agent", payload: liveContext.agentPayload(
                                title: "Waiting for first event",
                                detail: detail,
                                status: "running",
                                stage: .waitingFirstEvent,
                                health: .waiting,
                                phase: "planning",
                                liveEmitted: true
                            ))
                        )
                        continue
                    }
                    guard let lastMeaningfulEventAt = snapshot.lastMeaningfulEventAt,
                          now.timeIntervalSince(lastMeaningfulEventAt) >= SubagentExecutionRuntimeSettings.activeHeartbeatIdleSeconds else {
                        continue
                    }
                    let idleSeconds = Int(now.timeIntervalSince(lastMeaningfulEventAt))
                    let detail = "\(snapshot.currentDetail) • last update \(idleSeconds)s ago"
                    await liveState.markHeartbeat(detail: detail)
                    emitLiveOnly(
                        .raw(type: "agent", payload: liveContext.agentPayload(
                            title: "Heartbeat",
                            detail: detail,
                            status: "running",
                            stage: .toolActivity,
                            health: .active,
                            phase: "executing",
                            liveEmitted: true
                        ))
                    )
                }
            }

            group.addTask {
                try await Task.sleep(nanoseconds: 300_000_000_000)
                throw SubagentTimeoutError()
            }

            try await group.next()
            group.cancelAll()
        }

        let snapshot = await liveState.snapshot()
        if hasLiveCallback, !snapshot.hasMeaningfulEvent {
            throw SubagentNoMeaningfulEventError(
                roleName: role.displayName,
                backendName: liveContext.backendDisplayName,
                timeoutSeconds: Int(SubagentExecutionRuntimeSettings.firstMeaningfulEventDeadlineSeconds)
            )
        }

        return String(fullTextParts.joined().prefix(Self.subagentOutputLimit(for: role)))
    }
}
