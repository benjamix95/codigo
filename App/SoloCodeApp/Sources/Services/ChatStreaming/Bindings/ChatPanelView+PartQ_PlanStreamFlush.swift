import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    internal func clearPlanStreamingState() {
        flushPlanStreamingContent()
        if let targetConversationId = conversationId {
            planStreamingContentByConversation[targetConversationId] = ""
            planStreamingContent = ""
            if streaming.pendingPlanStreamConversationId == targetConversationId {
                streaming.pendingPlanStreamConversationId = nil
                streaming.pendingPlanStreamingContent = nil
            }
        } else {
            planStreamingContentByConversation.removeAll()
            planStreamingContent = ""
            streaming.pendingPlanStreamConversationId = nil
            streaming.pendingPlanStreamingContent = nil
        }
        streaming.planStreamThrottleTask?.cancel()
        streaming.planStreamThrottleTask = nil
    }

    internal func shouldRoutePlanStream(to conversationId: UUID?) -> Bool {
        let hasContext = hasActivePlanContext(for: conversationId)
        return shouldRoutePlanStreamToPlanPanel(
            shouldRoutePlanStreamingToPanel: shouldRoutePlanStreamingToPanel,
            streamConversationId: conversationId,
            hasActivePlanContext: hasContext,
            phase: planFlowPhase,
            activeBuildPlanConversationId: activeBuildPlanConversationId,
            activeBuildAgentConversationId: activeBuildAgentConversationId
        )
    }

    internal func updatePlanStreamingContent(_ content: String, conversationId: UUID?) {
        streaming.pendingPlanStreamConversationId = conversationId
        streaming.pendingPlanStreamingContent = content.count > 24_000
            ? String(content.suffix(24_000))
            : content

        if streaming.planStreamThrottleTask != nil { return }

        flushPlanStreamingContent()

        streaming.planStreamThrottleTask = Task {
            let delay = UInt64(planStreamThrottleInterval * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                flushPlanStreamingContent()
            }
        }
    }

    internal func appendPlanStreamingContent(_ content: String, conversationId: UUID?) {
        updatePlanStreamingContent(content, conversationId: conversationId)
    }

    internal func stripPlanCheckboxes(_ content: String) -> String {
        content.replacingOccurrences(
            of: #"(?m)^(\s*[-*]\s*)\[\s*[xX ]?\s*\]\s*"#,
            with: "$1",
            options: .regularExpression
        )
    }

    internal func flushPlanStreamingContent() {
        streaming.planStreamThrottleTask?.cancel()
        streaming.planStreamThrottleTask = nil
        guard let newContent = streaming.pendingPlanStreamingContent else {
            if let currentConversationId = conversationId {
                planStreamingContent = planStreamingContentByConversation[currentConversationId] ?? ""
            }
            return
        }
        let targetConversationId = streaming.pendingPlanStreamConversationId
        streaming.pendingPlanStreamingContent = nil
        streaming.pendingPlanStreamConversationId = nil
        if let targetConversationId {
            planStreamingContentByConversation[targetConversationId] = newContent
        }
        if let currentConversationId = conversationId {
            planStreamingContent = planStreamingContentByConversation[currentConversationId] ?? ""
        } else if targetConversationId == nil {
            planStreamingContent = newContent
        }
    }
}
