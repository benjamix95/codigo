import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    internal func continueIfPrematureStub(
        initial: String,
        provider: any LLMProvider,
        originalPrompt: String,
        context: WorkspaceContext,
        conversationId: UUID,
        hideContentDuringPlanDiscovery: Bool = false
    ) async throws -> String {
        var combinedText = initial
        let maxAutoContinuationRounds = 3
        var round = 0

        while shouldAutoContinueStub(combinedText),
              round < maxAutoContinuationRounds {
            round += 1
            let continuationPrompt = """
            Immediately continue your previous response and complete the task to a concrete outcome.
            Execute needed steps autonomously (analyze, act, verify, fix if needed) and do not stop at intentions.

            Original request:
            \(originalPrompt)

            Text already sent:
            \(combinedText)
            """

            let prior = combinedText
            let followUp = try await flowCoordinator.runStream(
                provider: provider,
                prompt: continuationPrompt,
                context: context,
                attachments: nil,
                onText: { deltaFull in
                    let combined = prior + "\n" + deltaFull
                    let displayContent = hideContentDuringPlanDiscovery
                        ? "Planning in progress… Open the Planning panel to see the result."
                        : combined
                    applyStreamingUpdate(
                        content: displayContent,
                        conversationId: conversationId
                    )
                },
                onRaw: { t, p, pid in
                    handleRawStreamEvent(type: t, payload: p, providerId: pid, conversationId: conversationId)
                },
                onError: { content in
                    DispatchQueue.main.async {
                        let combined = prior + "\n" + content
                        chatStore.updateLastAssistantMessage(content: combined, in: conversationId)
                    }
                },
                onSignal: nil
            )

            combinedText = prior + "\n" + followUp
        }

        return combinedText
    }

    internal func shouldAutoContinueStub(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let wordCount = trimmed.split(whereSeparator: \.isWhitespace).count
        guard wordCount <= 260 else { return false }
        let low = trimmed.lowercased()
        let stubSignals = [
            "i'll start",
            "i will start",
            "i'll begin",
            "i will begin",
            "first, i'll",
            "first i will",
            "let me start",
            "let me begin",
            "let me check",
            "i can continue",
            "would you like me to",
            "if you want i can",
            "next i'll",
            "next i will",
        ]
        if stubSignals.contains(where: { low.contains($0) }) {
            return true
        }
        if low.hasSuffix("...") || low.hasSuffix(":") {
            return true
        }
        return false
    }
}
