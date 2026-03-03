import Foundation

extension ToolEnabledLLMProvider {
    public func send(prompt: String, context: WorkspaceContext, imageURLs: [URL]? = nil) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        // When systemPromptOverride is set (e.g. prompt optimization), pass through to base without
        // adding taskCompletionStrict or toolProtocolPrompt — the context carries the custom system prompt.
        if context.systemPromptOverride != nil {
            return try await base.send(prompt: prompt, context: context, imageURLs: imageURLs)
        }

        // Keep native MCP tool registry aligned with current server/config state.
        // Registering is idempotent when the discovered tool set did not change.
        if policy.enableMCP {
            let discovered = await runtime.mcpSessions.discoverAllTools(
                idleTTLSeconds: policy.mcpSessionIdleTTLSeconds
            )
            _ = MCPNativeToolRegistry.shared.register(tools: discovered)
        } else if MCPNativeToolRegistry.shared.hasTools() {
            MCPNativeToolRegistry.shared.clear()
        }

        let initialPrompt = """
        \(SystemPrompts.taskCompletionStrict)

        \(toolProtocolPrompt)

        \(prompt)
        """

        return AsyncThrowingStream { continuation in
            let producerTask = Task {
                do {
                    try await self.streamToolExecution(
                        prompt: prompt,
                        context: context,
                        initialPrompt: initialPrompt,
                        imageURLs: imageURLs,
                        continuation: continuation
                    )
                    continuation.yield(.completed)
                    continuation.finish()
                } catch {
                    continuation.yield(.error(error.localizedDescription))
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                producerTask.cancel()
            }
        }
    }

    private func streamToolExecution(
        prompt: String,
        context: WorkspaceContext,
        initialPrompt: String,
        imageURLs: [URL]?,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        var currentPrompt = initialPrompt
        var conversationTranscript = ""
        var isFirstRound = true
        var extraContinuationRounds = 0
        var lastToolResultsForFallback: [[String: String]] = []
        var emittedVisibleTextAfterToolRound = false
        var hasAnyMeaningfulAssistantText = false
        let requiredPolicyHash = Self.requiredPolicyHash(from: context)
        var didEmitPolicyAck = false
        let enforceSubagentFirstRound = executionScope == .agent && subagentProviderFactory != nil
        var acceptedSubagentInFirstRound = false
        var sawCodeMutationDuringTask = false
        var reviewerCompletedAfterLatestMutation = false
        var testWriterCompletedAfterLatestMutation = false
        var mutatedPathsSinceLatestMutation: Set<String> = []
        var autoInjectedFinalReviewBatchCount = 0
        let maxAutoInjectedFinalReviewBatchCount = 4

        for _ in 0..<maxToolRounds {
            try Task.checkCancellation()
            await runtime.resetRoundCounters()
            let stream = try await base.send(
                prompt: currentPrompt,
                context: context,
                imageURLs: isFirstRound ? imageURLs : nil
            )

            var roundToolResults: [[String: String]] = []
            let roundResult = try await processToolRoundStream(
                stream: stream,
                context: context,
                isFirstRound: isFirstRound,
                requiredPolicyHash: requiredPolicyHash,
                enforceSubagentFirstRound: enforceSubagentFirstRound,
                acceptedSubagentInFirstRound: acceptedSubagentInFirstRound,
                didEmitPolicyAck: didEmitPolicyAck,
                continuation: continuation
            )

            didEmitPolicyAck = roundResult.didEmitPolicyAck
            acceptedSubagentInFirstRound = roundResult.acceptedSubagentInFirstRound
            roundToolResults.append(contentsOf: roundResult.roundToolResults)
            let roundText = roundResult.roundText

            if roundResult.didEmitMeaningfulText {
                hasAnyMeaningfulAssistantText = true
                emittedVisibleTextAfterToolRound = true
            }

            if roundResult.sawCodeMutationDuringTask {
                sawCodeMutationDuringTask = true
                reviewerCompletedAfterLatestMutation = roundResult.reviewerCompletedAfterLatestMutation
                testWriterCompletedAfterLatestMutation = roundResult.testWriterCompletedAfterLatestMutation
                mutatedPathsSinceLatestMutation.formUnion(roundResult.mutatedPaths)
            } else {
                reviewerCompletedAfterLatestMutation = reviewerCompletedAfterLatestMutation || roundResult.reviewerCompletedAfterLatestMutation
                testWriterCompletedAfterLatestMutation = testWriterCompletedAfterLatestMutation || roundResult.testWriterCompletedAfterLatestMutation
            }

            if !roundResult.pendingSubagentCalls.isEmpty {
                let subagentBatch = await executeSubagentCallBatch(
                    calls: roundResult.pendingSubagentCalls,
                    context: context,
                    requiredPolicyHash: requiredPolicyHash,
                    continuation: continuation
                )

                didEmitPolicyAck = didEmitPolicyAck || subagentBatch.didEmitPolicyAck
                if subagentBatch.sawCodeMutationDuringTask {
                    sawCodeMutationDuringTask = true
                    reviewerCompletedAfterLatestMutation = subagentBatch.reviewerCompletedAfterLatestMutation
                    testWriterCompletedAfterLatestMutation = subagentBatch.testWriterCompletedAfterLatestMutation
                    mutatedPathsSinceLatestMutation.formUnion(subagentBatch.mutatedPaths)
                } else {
                    reviewerCompletedAfterLatestMutation = reviewerCompletedAfterLatestMutation || subagentBatch.reviewerCompletedAfterLatestMutation
                    testWriterCompletedAfterLatestMutation = testWriterCompletedAfterLatestMutation || subagentBatch.testWriterCompletedAfterLatestMutation
                }
                roundToolResults.append(contentsOf: subagentBatch.roundToolResults)
            }

            let mandatoryReviewSatisfied =
                reviewerCompletedAfterLatestMutation && testWriterCompletedAfterLatestMutation
            if subagentProviderFactory != nil,
               sawCodeMutationDuringTask,
               !mandatoryReviewSatisfied,
               autoInjectedFinalReviewBatchCount < maxAutoInjectedFinalReviewBatchCount
            {
                autoInjectedFinalReviewBatchCount += 1
                let injectedCalls = buildAutoInjectedReviewCalls(
                    sawReviewerComplete: reviewerCompletedAfterLatestMutation,
                    sawTestWriterComplete: testWriterCompletedAfterLatestMutation,
                    modifiedPaths: mutatedPathsSinceLatestMutation
                )
                if !injectedCalls.isEmpty {
                    let injectedBatch = await executeSubagentCallBatch(
                        calls: injectedCalls,
                        context: context,
                        requiredPolicyHash: requiredPolicyHash,
                        continuation: continuation,
                        emitStartedEvents: true
                    )
                    if injectedBatch.anyFailed {
                        // Stop retrying — subagent failures are likely deterministic
                        autoInjectedFinalReviewBatchCount = maxAutoInjectedFinalReviewBatchCount
                    }
                    if injectedBatch.sawCodeMutationDuringTask {
                        sawCodeMutationDuringTask = true
                        reviewerCompletedAfterLatestMutation = injectedBatch.reviewerCompletedAfterLatestMutation
                        testWriterCompletedAfterLatestMutation = injectedBatch.testWriterCompletedAfterLatestMutation
                        mutatedPathsSinceLatestMutation.formUnion(injectedBatch.mutatedPaths)
                    } else {
                        reviewerCompletedAfterLatestMutation = reviewerCompletedAfterLatestMutation || injectedBatch.reviewerCompletedAfterLatestMutation
                        testWriterCompletedAfterLatestMutation = testWriterCompletedAfterLatestMutation || injectedBatch.testWriterCompletedAfterLatestMutation
                    }
                    didEmitPolicyAck = didEmitPolicyAck || injectedBatch.didEmitPolicyAck
                    roundToolResults.append(contentsOf: injectedBatch.roundToolResults)
                }
            }

            let mandatoryReviewSatisfiedAfterRound =
                reviewerCompletedAfterLatestMutation && testWriterCompletedAfterLatestMutation
            if mandatoryReviewSatisfiedAfterRound {
                mutatedPathsSinceLatestMutation.removeAll()
            }

            conversationTranscript += "\n[assistant]\n\(roundText)\n"
            if conversationTranscript.count > 48_000 {
                conversationTranscript = String(conversationTranscript.suffix(40_000))
            }
            if !roundToolResults.isEmpty {
                lastToolResultsForFallback = roundToolResults
                emittedVisibleTextAfterToolRound = false
            }

            var shouldContinue = !roundToolResults.isEmpty || roundResult.sawExecutableSuggestion
            if !shouldContinue,
               shouldForceAutonomousContinuation(
                roundText,
                roundIndex: extraContinuationRounds
               ),
               extraContinuationRounds < maxAutonomousContinuationRounds
            {
                shouldContinue = true
                extraContinuationRounds += 1
            }
            guard shouldContinue else { break }

            currentPrompt = buildFollowUpPrompt(
                originalPrompt: prompt,
                transcript: conversationTranscript,
                toolResults: roundToolResults
            )
            isFirstRound = false
        }

        if !lastToolResultsForFallback.isEmpty && !emittedVisibleTextAfterToolRound {
            let meaningfulAfterForced = try await emitForcedFinalization(
                prompt: prompt,
                context: context,
                transcript: conversationTranscript,
                toolResults: lastToolResultsForFallback,
                continuation: continuation
            )
            if meaningfulAfterForced {
                hasAnyMeaningfulAssistantText = true
            }
        }

        if !hasAnyMeaningfulAssistantText && !lastToolResultsForFallback.isEmpty {
            continuation.yield(.raw(type: "tool_execution_error", payload: [
                "title": "Missing final output",
                "detail": "No meaningful final content produced",
                "status": "failed",
                "error_code": "missing_final_outcome"
            ]))
        }

        if subagentProviderFactory != nil,
           sawCodeMutationDuringTask,
           !(reviewerCompletedAfterLatestMutation && testWriterCompletedAfterLatestMutation)
        {
            continuation.yield(.raw(type: "tool_validation_error", payload: [
                "title": "Mandatory review incomplete",
                "detail": "Code mutations were detected, but reviewer/testWriter coverage for the latest changes is incomplete.",
                "status": "failed",
                "error_code": "mandatory_review_incomplete"
            ]))
        }
    }

}
