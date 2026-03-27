import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    @MainActor
    internal func recoverPolicyAckFromPersistedAssistantMessageIfNeeded(
        assistantMessageId: UUID,
        providerId: String,
        conversationId: UUID
    ) {
        guard let state = toolRuntime.policyAckStateByMessage[assistantMessageId],
              !state.isSatisfied else {
            return
        }
        let persistedContent = chatStore.conversation(for: conversationId)?
            .messages
            .first(where: { $0.id == assistantMessageId })?
            .resolvedPrimaryText ?? ""
        guard !persistedContent.isEmpty else { return }

        let matchingHash = inlinePolicyAckHashes(in: persistedContent).first {
            $0 == state.expectedHash
        }
        guard let matchingHash else { return }

        let enriched = processPolicyAckEvent(
            payload: [
                "hash": matchingHash,
                "title": "Policy acknowledged",
                "detail": "Policy hash recovered from persisted assistant content",
            ],
            providerId: providerId,
            conversationId: conversationId
        )
        recordTaskActivity(
            type: "policy_ack",
            payload: enriched,
            providerId: providerId,
            conversationId: conversationId
        )
        flushPolicyAckBlockedQueue(
            providerId: providerId,
            conversationId: conversationId
        )
    }

    @MainActor
    internal func processInlinePolicyAckMarkers(
        in content: String,
        providerId: String,
        conversationId: UUID?
    ) {
        let hashes = inlinePolicyAckHashes(in: content)
        guard !hashes.isEmpty else { return }

        for hash in hashes {
            guard let turn = resolveToolTraceTurn(
                conversationId: conversationId,
                providerId: providerId
            ) else {
                return
            }
            let stateBeforeInlineAck = toolRuntime.policyAckStateByMessage[turn.assistantMessageId]
            // #region agent log
            RuntimeEvidenceDebugLog.appendThrottled(
                gateKey: "H42-inline-policy-ack-\(turn.assistantMessageId.uuidString)-\(hash)",
                minInterval: 0.05,
                hypothesisId: "H42",
                location: "processInlinePolicyAckMarkers",
                message: "inline_policy_ack_marker_detected",
                data: [
                    "conversationId": conversationId?.uuidString ?? "nil",
                    "assistantMessageId": turn.assistantMessageId.uuidString,
                    "contentLen": "\(content.count)",
                    "receivedHash": hash,
                    "expectedHash": stateBeforeInlineAck?.expectedHash ?? "",
                    "acknowledgedHashBefore": stateBeforeInlineAck?.acknowledgedHash ?? "",
                    "isSatisfiedBefore": "\(stateBeforeInlineAck?.isSatisfied == true)",
                ]
            )
            // #endregion
            if toolRuntime.policyAckStateByMessage[turn.assistantMessageId]?.acknowledgedHash == hash {
                continue
            }

            let enriched = processPolicyAckEvent(
                payload: [
                    "hash": hash,
                    "title": "Policy acknowledged",
                    "detail": "Policy hash accepted (inline marker)",
                ],
                providerId: providerId,
                conversationId: conversationId
            )
            recordTaskActivity(
                type: "policy_ack",
                payload: enriched,
                providerId: providerId,
                conversationId: conversationId
            )

            switch policyAckDisposition(status: enriched["status"]) {
            case .acknowledged:
                flushPolicyAckBlockedQueue(
                    providerId: providerId,
                    conversationId: conversationId
                )
            case .invalid:
                appendTechnicalErrorMessage(
                    "[Policy error] Invalid AGENTS/SKILL acknowledgment received. Expected hash \(enriched["expected_hash"] ?? "?").",
                    in: conversationId
                )
                stopTaskForPolicyViolation(
                    conversationId: conversationId,
                    reason: "policy_ack_inline_invalid"
                )
                return
            case .ignored:
                break
            }
        }
    }

    @MainActor
    internal func processPolicyAckEvent(
        payload: [String: String],
        providerId: String,
        conversationId: UUID?
    ) -> [String: String] {
        guard let turn = resolveToolTraceTurn(conversationId: conversationId, providerId: providerId) else {
            return payload
        }
        guard var state = toolRuntime.policyAckStateByMessage[turn.assistantMessageId] else {
            return payload
        }

        let receivedHash = (payload["hash"] ?? payload["policy_hash"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let wasSatisfiedBefore = state.isSatisfied
        let acknowledgedHashBefore = state.acknowledgedHash
        var enriched = payload
        enriched["expected_hash"] = state.expectedHash

        if receivedHash == state.expectedHash {
            state.acknowledgedHash = receivedHash
            state.violationEmitted = false
            toolRuntime.policyAckFailedMessages.remove(turn.assistantMessageId)
            enriched["status"] = "acknowledged"
            enriched["title"] = payload["title"] ?? "Policy acknowledged"
            enriched["detail"] = payload["detail"] ?? "Policy hash accepted"
        } else {
            toolRuntime.policyAckFailedMessages.insert(turn.assistantMessageId)
            enriched["status"] = "invalid"
            enriched["title"] = payload["title"] ?? "Policy acknowledgment invalid"
            enriched["detail"] = payload["detail"] ?? "Expected hash \(state.expectedHash)"
        }
        // #region agent log
        RuntimeEvidenceDebugLog.append(
            hypothesisId: "H43",
            location: "processPolicyAckEvent",
            message: "policy_ack_event_processed",
            data: [
                "conversationId": conversationId?.uuidString ?? "nil",
                "assistantMessageId": turn.assistantMessageId.uuidString,
                "receivedHash": receivedHash,
                "expectedHash": state.expectedHash,
                "acknowledgedHashBefore": acknowledgedHashBefore ?? "",
                "status": enriched["status"] ?? "",
                "wasSatisfiedBefore": "\(wasSatisfiedBefore)",
                "isSatisfiedAfter": "\(state.isSatisfied)",
            ]
        )
        // #endregion
        toolRuntime.policyAckStateByMessage[turn.assistantMessageId] = state
        return enriched
    }
}
