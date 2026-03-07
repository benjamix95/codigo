import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    @MainActor
    internal func handleCodeReviewPanelAction(_ action: CodeReviewPanelAction) {
        switch action {
        case .quickCommand(let id):
            guard let command = CodeReviewQuickCommands.defaults.first(where: { $0.id == id }) else {
                return
            }
            dispatchCodeReviewPrompt(command.prompt)
        case .againstCommit(let ref, let autofixEnabled, let maxRounds):
            let prompt = CodeReviewQuickCommands.againstPrompt(
                ref: ref,
                autofixEnabled: autofixEnabled,
                maxRounds: maxRounds
            )
            dispatchCodeReviewPrompt(prompt)
        case .rerunSession(let sessionId):
            guard let snapshot = selectedCodeReviewSnapshot(sessionId: sessionId) else { return }
            dispatchCodeReviewPrompt(
                reReviewPrompt(for: snapshot),
                sessionConfigOverride: snapshot.config
            )
        case .applyFix(let sessionId, let findingId):
            Task { @MainActor in
                await applyInlineReviewFixes(
                    sessionId: sessionId,
                    findingIds: [findingId]
                )
            }
        case .dismissFinding(let sessionId, let findingId, let reason):
            Task { @MainActor in
                await dismissInlineReviewFindings(
                    sessionId: sessionId,
                    findingIds: [findingId],
                    reason: reason
                )
            }

        case .applyAllFixes(let sessionId, let findingIds):
            Task { @MainActor in
                await applyInlineReviewFixes(
                    sessionId: sessionId,
                    findingIds: findingIds
                )
            }

        case .dismissAll(let sessionId, let findingIds, let reason):
            Task { @MainActor in
                await dismissInlineReviewFindings(
                    sessionId: sessionId,
                    findingIds: findingIds,
                    reason: reason
                )
            }

        case .exportSummary(let sessionId):
            publishCodeReviewSummary(sessionId: sessionId)
        }
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

extension ChatPanelView {
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

    func reReviewPrompt(for snapshot: CodeReviewSessionSnapshot) -> String {
        switch snapshot.scope?.type {
        case .againstRef:
            return CodeReviewQuickCommands.againstPrompt(
                ref: snapshot.scope?.ref ?? "HEAD~1",
                autofixEnabled: !codeReviewAnalysisOnly,
                maxRounds: snapshot.config.maxRounds
            )
        case .staged:
            return """
            [REVIEW_SCOPE:staged] Re-run code review for session \(snapshot.sessionId).
            Focus on unresolved findings, regressions from previous fixes, and any remaining high-risk issues.
            """
        case .uncommitted, .none:
            return """
            [REVIEW_SCOPE:uncommitted] Re-run code review for session \(snapshot.sessionId).
            Focus on unresolved findings, regressions from previous fixes, and any remaining high-risk issues.
            """
        }
    }

    @MainActor
    func publishCodeReviewSummary(sessionId: String) {
        guard let conversationId,
              let snapshot = selectedCodeReviewSnapshot(sessionId: sessionId) else {
            return
        }
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
}
