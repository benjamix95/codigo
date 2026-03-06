import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    internal func stripPlanCheckboxes(_ content: String) -> String {
        content.replacingOccurrences(
            of: #"(?m)^(\s*[-*]\s*)\[\s*[xX ]?\s*\]\s*"#,
            with: "$1",
            options: .regularExpression
        )
    }

    internal func applyStreamingUpdate(
        content: String,
        conversationId: UUID?
    ) {
        let shouldSanitize = isPlanBuildContext(
            conversationId: conversationId,
            phase: planFlowPhase,
            activeBuildPlanConversationId: activeBuildPlanConversationId,
            activeBuildAgentConversationId: activeBuildAgentConversationId
        )
        let sanitizedContent = shouldSanitize ? stripPlanCheckboxes(content) : content
        let shouldRouteToPlanPanel = shouldRoutePlanStream(to: conversationId)

        if shouldRouteToPlanPanel {
            appendPlanStreamingContent(
                sanitizedContent,
                conversationId: conversationId
            )
            if shouldAutoOpenPlanPanel(trigger: .flowStarted), !showPlanPanel {
                openPlanPanelForCurrentContext(
                    preserveHistorySelection: false,
                    source: .automaticFlow
                )
            }
        }

        if conversationId != self.conversationId {
            applyLegacyStreamSnapshot(
                content: sanitizedContent,
                conversationId: conversationId,
                providerId: resolvedTurnProviderId(for: conversationId)
            )
            return
        }

        pendingStreamContent = sanitizedContent
        pendingStreamConversationId = conversationId
        updateStreamingTextSegment(sanitizedContent)

        if streamThrottleTask != nil { return }
        flushStreamingContent()

        streamThrottleTask = Task {
            let delay = UInt64(streamThrottleInterval * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                streamThrottleTask = nil
                guard let pending = pendingStreamContent else { return }
                pendingStreamContent = nil
                let shouldSanitizePending = isPlanBuildContext(
                    conversationId: pendingStreamConversationId,
                    phase: planFlowPhase,
                    activeBuildPlanConversationId: activeBuildPlanConversationId,
                    activeBuildAgentConversationId: activeBuildAgentConversationId
                )
                applyLegacyStreamSnapshot(
                    content: shouldSanitizePending ? stripPlanCheckboxes(pending) : pending,
                    conversationId: pendingStreamConversationId,
                    providerId: resolvedTurnProviderId(for: pendingStreamConversationId)
                )
                streamContentVersion &+= 1
            }
        }
    }

    internal func flushStreamingContent() {
        streamThrottleTask?.cancel()
        streamThrottleTask = nil
        guard let content = pendingStreamContent else { return }
        pendingStreamContent = nil
        let shouldSanitizePending = isPlanBuildContext(
            conversationId: pendingStreamConversationId,
            phase: planFlowPhase,
            activeBuildPlanConversationId: activeBuildPlanConversationId,
            activeBuildAgentConversationId: activeBuildAgentConversationId
        )
        let sanitizedContent = shouldSanitizePending ? stripPlanCheckboxes(content) : content
        applyLegacyStreamSnapshot(
            content: sanitizedContent,
            conversationId: pendingStreamConversationId,
            providerId: resolvedTurnProviderId(for: pendingStreamConversationId)
        )
        streamContentVersion &+= 1
    }

    internal func updateStreamingTextSegment(_ content: String) {
        guard sequentialStreamingLayoutEnabled else { return }
        let segId = "text-\(streamingSegmentTurnIndex)"
        if content.isEmpty {
            streamingSegments.removeAll { $0.id == segId }
            return
        }
        if let idx = streamingSegments.firstIndex(where: { $0.id == segId }) {
            streamingSegments[idx].kind = .text(content)
        } else {
            streamingSegments.append(MessageSegment(id: segId, kind: .text(content)))
        }
    }
}
