import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    /// Retained for backward-compat: the MCP `processCodeReviewCommandLoop`
    /// path still uses this method to inject a review prompt into the main chat.
    @MainActor
    func dispatchCodeReviewPrompt(
        _ prompt: String,
        sessionConfigOverride: SessionConfig? = nil
    ) {
        pendingCodeReviewSessionConfigOverride = sessionConfigOverride
        inputText = prompt
        isInputFocused = true
        if coderMode != .codeReviewMultiSwarm {
            selectMode(.codeReviewMultiSwarm)
        }
        sendMessage(preferCodeReviewRuntimeProvider: true)
    }

    /// Opt-in action: publish a code review summary into the main chat thread.
    @MainActor
    func publishCodeReviewSummary(sessionId: String) {
        guard let conversationId,
              let snapshot = selectedCodeReviewSnapshot(sessionId: sessionId)
        else { return }

        let header = """
        ## Code Review Summary
        - session_id: \(snapshot.sessionId)
        - phase: \(snapshot.phase.rawValue)
        - stage: \(snapshot.stage.rawValue)
        - scope: \(snapshot.scope?.description ?? "unknown")
        - findings: \(snapshot.findings.count)
        """
        let findings = snapshot.findings.map { finding in
            let line = finding.lineNumber.map { ":\($0)" } ?? ""
            return "- [\(finding.severity.rawValue)] \(finding.filePath)\(line) — \(finding.message)"
        }
        let content = ([header] + findings).joined(separator: "\n")
        chatStore.addMessage(
            ChatMessage(role: .assistant, content: content, isStreaming: false),
            to: conversationId
        )
    }

    @MainActor
    internal func handleSyntheticCodeReviewToolEvent(
        type _: String,
        payload _: [String: String],
        conversationId _: UUID?
    ) -> Bool {
        false
    }
}
