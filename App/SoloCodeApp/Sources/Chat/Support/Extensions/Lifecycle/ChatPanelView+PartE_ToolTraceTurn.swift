import Foundation
import CoderEngine

private enum PolicyBundleLookupCache {
    static let ttl: TimeInterval = 2
    static let lock = NSLock()
    static nonisolated(unsafe) var byKey: [String: (bundle: InstructionPolicyBundle, createdAt: Date)] = [:]

    static func key(for hints: [String]) -> String {
        hints
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
            .joined(separator: "|")
    }

    static func lookup(for hints: [String]) -> InstructionPolicyBundle {
        let cacheKey = key(for: hints)
        let now = Date()

        lock.lock()
        if let cached = byKey[cacheKey], now.timeIntervalSince(cached.createdAt) <= ttl {
            lock.unlock()
            return cached.bundle
        }
        lock.unlock()

        let bundle = InstructionPolicyBundle.load(workspacePaths: hints)

        lock.lock()
        byKey[cacheKey] = (bundle, now)
        if byKey.count > 64 {
            let staleCutoff = now.addingTimeInterval(-ttl)
            byKey = byKey.filter { _, entry in
                entry.createdAt >= staleCutoff
            }
        }
        lock.unlock()
        return bundle
    }
}

extension ChatPanelView {
    internal func currentInstructionPolicyBundle() -> InstructionPolicyBundle {
        let hints = traceWorkspaceHints(for: effectiveContext)
        return PolicyBundleLookupCache.lookup(for: hints)
    }

    internal func expectedPolicyAckHash() -> String? {
        guard agentsHardBlockEnabled else { return nil }
        let bundle = currentInstructionPolicyBundle()
        let hash = bundle.policyHash.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hash.isEmpty else { return nil }
        return hash
    }

    internal func initializePolicyAckStateIfNeeded(for assistantMessageId: UUID) {
        guard let expectedHash = expectedPolicyAckHash() else {
            policyAckStateByMessage.removeValue(forKey: assistantMessageId)
            policyAckFailedMessages.remove(assistantMessageId)
            return
        }
        guard !policyAckFailedMessages.contains(assistantMessageId) else { return }
        if policyAckStateByMessage[assistantMessageId] == nil {
            policyAckStateByMessage[assistantMessageId] = PolicyAckState(expectedHash: expectedHash)
        }
    }

    @MainActor
    internal func startToolTraceTurn(conversationId: UUID, assistantMessageId: UUID, providerId: String) {
        if let previous = activeToolTraceTurnsByConversation[conversationId],
           previous.assistantMessageId != assistantMessageId {
            let previousEvents = toolTraceStore.events(
                conversationId: previous.conversationId,
                assistantMessageId: previous.assistantMessageId
            )
            let hasRunningOperations = previousEvents.contains { $0.isRunning }
            let rolloverOutcome: ToolTraceTurnOutcome = hasRunningOperations ? .aborted : .success
            let previousPolicySatisfied = policyAckStateByMessage[previous.assistantMessageId]?.isSatisfied == true
            finalizeAutoTodoIfNeeded(
                messageId: previous.assistantMessageId,
                outcome: rolloverOutcome,
                providerId: previous.providerId,
                conversationId: previous.conversationId
            )
            toolTraceStore.finalizeTurn(
                conversationId: previous.conversationId,
                assistantMessageId: previous.assistantMessageId
            )
            toolTraceNextSequenceByMessage.removeValue(forKey: previous.assistantMessageId)
            toolTraceOperationalSeenByMessage.removeValue(forKey: previous.assistantMessageId)
            toolTraceOperationalCountByMessage.removeValue(forKey: previous.assistantMessageId)
            policyAckStateByMessage.removeValue(forKey: previous.assistantMessageId)
            // Flush any remaining blocked events before discarding the queue
            if let remainingQueued = policyAckBlockedQueue.removeValue(forKey: previous.assistantMessageId), !remainingQueued.isEmpty {
                if previousPolicySatisfied {
                    for event in remainingQueued {
                        handleRawStreamEvent(
                            type: event.type,
                            payload: event.payload,
                            providerId: event.providerId,
                            conversationId: event.conversationId,
                            shouldApplyPipelineArtifacts: event.shouldApplyPipelineArtifacts
                        )
                    }
                } else {
                    appendTechnicalErrorMessage(
                        "[Policy error] Required AGENTS/SKILL acknowledgment did not arrive before the turn was closed.",
                        in: previous.conversationId
                    )
                }
            }
            policyAckFailedMessages.remove(previous.assistantMessageId)
            autoTodoRuntimeStateByMessage.removeValue(
                forKey: previous.assistantMessageId.uuidString.lowercased()
            )
            didReceiveExplicitTodoByMessage.remove(previous.assistantMessageId)
        }
        let turn = ToolTraceTurnContext(
            conversationId: conversationId,
            assistantMessageId: assistantMessageId,
            providerId: providerId
        )
        activeToolTraceTurnsByConversation[conversationId] = turn
        toolTraceNextSequenceByMessage[assistantMessageId] = 1
        toolTraceOperationalSeenByMessage[assistantMessageId] = false
        toolTraceOperationalCountByMessage[assistantMessageId] = 0
        autoTodoRuntimeStateByMessage.removeValue(forKey: assistantMessageId.uuidString.lowercased())
        didReceiveExplicitTodoByMessage.remove(assistantMessageId)
        if isSwarmPolicyAckExemptProvider(providerId) {
            policyAckStateByMessage.removeValue(forKey: assistantMessageId)
            policyAckFailedMessages.remove(assistantMessageId)
        } else {
            initializePolicyAckStateIfNeeded(for: assistantMessageId)
        }
        toolTraceStore.startTurn(
            conversationId: conversationId,
            assistantMessageId: assistantMessageId,
            providerId: providerId
        )
    }

    @MainActor
    internal func finalizeToolTraceTurn(conversationId: UUID?, outcome: ToolTraceTurnOutcome? = nil) {
        let finalOutcome = outcome ?? toolTraceTurnOutcome(for: flowCoordinator.state)

        if let conversationId {
            guard let active = activeToolTraceTurnsByConversation[conversationId] else { return }
            finalizeToolTraceTurn(active, outcome: finalOutcome)
            activeToolTraceTurnsByConversation.removeValue(forKey: conversationId)
            return
        }

        let activeTurns = Array(activeToolTraceTurnsByConversation.values)
        for active in activeTurns {
            finalizeToolTraceTurn(active, outcome: finalOutcome)
        }
        activeToolTraceTurnsByConversation.removeAll()
    }
}
