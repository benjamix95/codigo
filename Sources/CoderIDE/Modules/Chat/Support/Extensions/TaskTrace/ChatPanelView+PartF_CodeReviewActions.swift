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
            dispatchCodeReviewPrompt(reReviewPrompt(for: snapshot))

        case .applyFix(let sessionId, let findingId):
            guard let snapshot = selectedCodeReviewSnapshot(sessionId: sessionId),
                  let finding = snapshot.findings.first(where: { $0.id == findingId }) else {
                return
            }
            Task {
                _ = await ReviewSessionRegistry.shared.applyFix(
                    sessionId: sessionId,
                    findingId: findingId
                )
            }
            dispatchCodeReviewPrompt(targetedFixPrompt(for: snapshot, findings: [finding]))

        case .dismissFinding(let sessionId, let findingId, let reason):
            Task {
                _ = await ReviewSessionRegistry.shared.dismissFinding(
                    sessionId: sessionId,
                    findingId: findingId,
                    reason: reason
                )
            }

        case .applyAllFixes(let sessionId, let findingIds):
            guard let snapshot = selectedCodeReviewSnapshot(sessionId: sessionId) else { return }
            let findings = snapshot.findings.filter { findingIds.contains($0.id) }
            guard !findings.isEmpty else { return }
            Task {
                for findingId in findingIds {
                    _ = await ReviewSessionRegistry.shared.applyFix(
                        sessionId: sessionId,
                        findingId: findingId
                    )
                }
            }
            dispatchCodeReviewPrompt(targetedFixPrompt(for: snapshot, findings: findings))

        case .dismissAll(let sessionId, let findingIds, let reason):
            Task {
                for findingId in findingIds {
                    _ = await ReviewSessionRegistry.shared.dismissFinding(
                        sessionId: sessionId,
                        findingId: findingId,
                        reason: reason
                    )
                }
            }

        case .exportSummary(let sessionId):
            publishCodeReviewSummary(sessionId: sessionId)
        }
    }

    @MainActor
    internal func handleSyntheticCodeReviewToolEvent(
        type: String,
        payload: [String: String],
        conversationId: UUID?
    ) -> Bool {
        let targetConversationId = conversationId ?? self.conversationId
        switch type {
        case "review_apply_fix":
            guard let sessionId = payload["session_id"],
                  let findingId = payload["finding_id"] else {
                return false
            }
            Task {
                _ = await ReviewSessionRegistry.shared.applyFix(
                    sessionId: sessionId,
                    findingId: findingId
                )
            }
            return true

        case "review_dismiss":
            guard let sessionId = payload["session_id"],
                  let findingId = payload["finding_id"] else {
                return false
            }
            let reason = payload["reason"] ?? "dismissed"
            Task {
                _ = await ReviewSessionRegistry.shared.dismissFinding(
                    sessionId: sessionId,
                    findingId: findingId,
                    reason: reason
                )
            }
            return true

        case "review_comment":
            guard let sessionId = payload["session_id"],
                  let findingId = payload["finding_id"],
                  let content = payload["content"] else {
                return false
            }
            let author = payload["author"] ?? "agent"
            Task {
                _ = await ReviewSessionRegistry.shared.addComment(
                    sessionId: sessionId,
                    findingId: findingId,
                    comment: FindingComment(author: author, content: content)
                )
            }
            return true

        case "review_configure":
            guard let sessionId = payload["session_id"] else { return false }
            guard let snapshot = taskActivityStore.codeReviewSnapshot(
                sessionId: sessionId,
                conversationId: targetConversationId
            ) else {
                return false
            }
            let config = SessionConfig(
                maxWorkers: Int(payload["max_workers"] ?? "") ?? snapshot.config.maxWorkers,
                maxRounds: Int(payload["max_rounds"] ?? "") ?? snapshot.config.maxRounds,
                analysisBackend: payload["analysis_backend"] ?? snapshot.config.analysisBackend,
                executionBackend: payload["execution_backend"] ?? snapshot.config.executionBackend
            )
            Task {
                _ = await ReviewSessionRegistry.shared.updateConfig(
                    sessionId: sessionId,
                    config: config
                )
            }
            return true

        default:
            return false
        }
    }
}

private extension ChatPanelView {
    @MainActor
    func selectedCodeReviewSnapshot(sessionId: String) -> CodeReviewSessionSnapshot? {
        taskActivityStore.codeReviewSnapshot(
            sessionId: sessionId,
            conversationId: conversationId
        )
    }

    @MainActor
    func dispatchCodeReviewPrompt(_ prompt: String) {
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
                maxRounds: codeReviewMaxRounds
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

    func targetedFixPrompt(
        for snapshot: CodeReviewSessionSnapshot,
        findings: [CodeReviewFinding]
    ) -> String {
        let files = Array(Set(findings.map(\.filePath))).sorted()
        let findingsList = findings.map { finding in
            let line = finding.lineNumber.map { ":\($0)" } ?? ""
            return "- \(finding.filePath)\(line) [\(finding.severity.rawValue)] \(finding.message)"
        }.joined(separator: "\n")
        let scopePrefix: String = {
            switch snapshot.scope?.type {
            case .staged:
                return "[REVIEW_SCOPE:staged]"
            case .againstRef:
                return "[AGAINST:\(snapshot.scope?.ref ?? "HEAD~1")]"
            case .uncommitted, .none:
                return "[REVIEW_SCOPE:uncommitted]"
            }
        }()
        return """
        \(scopePrefix) Apply targeted fixes for the selected code review findings in session \(snapshot.sessionId).
        Files in scope:
        \(files.joined(separator: "\n"))

        Findings to fix:
        \(findingsList)

        Requirements:
        - fix only the listed findings,
        - keep changes minimal and localized,
        - run relevant verification after changes,
        - report what was fixed and any residual risks.
        """
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
