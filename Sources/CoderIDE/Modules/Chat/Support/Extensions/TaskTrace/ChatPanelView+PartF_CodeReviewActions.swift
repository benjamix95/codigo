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

private extension ChatPanelView {
    @MainActor
    func applyInlineReviewFixes(
        sessionId: String,
        findingIds: [String]
    ) async {
        if let liveState = await ReviewSessionRegistry.shared.state(sessionId: sessionId) {
            var didChange = false
            for findingId in findingIds {
                didChange = await liveState.applyFix(findingId: findingId) || didChange
            }
            if didChange {
                let snapshot = await liveState.snapshot()
                taskActivityStore.ingestCodeReviewSnapshot(
                    snapshot,
                    conversationId: conversationId
                )
            }
            return
        }

        guard let snapshot = selectedCodeReviewSnapshot(sessionId: sessionId) else { return }
        let updatedFindings = snapshot.findings.map { finding in
            guard findingIds.contains(finding.id) else { return finding }
            var updated = finding
            updated.status = .fixApplied
            return updated
        }
        let changedCount = zip(snapshot.findings, updatedFindings)
            .filter { $0.status != $1.status }
            .count
        guard changedCount > 0 else { return }
        let updatedSnapshot = CodeReviewSessionSnapshot(
            sessionId: snapshot.sessionId,
            conversationId: snapshot.conversationId,
            mutationSequence: snapshot.mutationSequence + 1,
            phase: snapshot.phase,
            stage: snapshot.stage,
            findings: updatedFindings,
            events: snapshot.events + findingIds.map {
                CodeReviewSessionEvent.findingFixApplied(findingId: $0)
            },
            config: snapshot.config,
            scope: snapshot.scope,
            workspacePath: snapshot.workspacePath,
            currentRound: snapshot.currentRound,
            activeWorkerCount: snapshot.activeWorkerCount,
            startedAt: snapshot.startedAt,
            completedAt: snapshot.completedAt,
            analysisCompletedAt: snapshot.analysisCompletedAt,
            lastError: snapshot.lastError,
            currentJobId: snapshot.currentJobId,
            lastTestStatus: snapshot.lastTestStatus,
            lastUpdatedAt: Date()
        )
        taskActivityStore.ingestCodeReviewSnapshot(updatedSnapshot, conversationId: conversationId)
    }

    @MainActor
    func dismissInlineReviewFindings(
        sessionId: String,
        findingIds: [String],
        reason: String
    ) async {
        if let liveState = await ReviewSessionRegistry.shared.state(sessionId: sessionId) {
            var didChange = false
            for findingId in findingIds {
                didChange = await liveState.dismissFinding(
                    findingId: findingId,
                    reason: reason
                ) || didChange
            }
            if didChange {
                let snapshot = await liveState.snapshot()
                taskActivityStore.ingestCodeReviewSnapshot(
                    snapshot,
                    conversationId: conversationId
                )
            }
            return
        }

        guard let snapshot = selectedCodeReviewSnapshot(sessionId: sessionId) else { return }
        let status: FindingStatus = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() == FindingStatus.wontFix.rawValue ? .wontFix : .dismissed
        let updatedFindings = snapshot.findings.map { finding in
            guard findingIds.contains(finding.id) else { return finding }
            var updated = finding
            updated.status = status
            return updated
        }
        let changedCount = zip(snapshot.findings, updatedFindings)
            .filter { $0.status != $1.status }
            .count
        guard changedCount > 0 else { return }
        let updatedSnapshot = CodeReviewSessionSnapshot(
            sessionId: snapshot.sessionId,
            conversationId: snapshot.conversationId,
            mutationSequence: snapshot.mutationSequence + 1,
            phase: snapshot.phase,
            stage: snapshot.stage,
            findings: updatedFindings,
            events: snapshot.events + findingIds.map {
                CodeReviewSessionEvent.findingDismissed(findingId: $0, reason: reason)
            },
            config: snapshot.config,
            scope: snapshot.scope,
            workspacePath: snapshot.workspacePath,
            currentRound: snapshot.currentRound,
            activeWorkerCount: snapshot.activeWorkerCount,
            startedAt: snapshot.startedAt,
            completedAt: snapshot.completedAt,
            analysisCompletedAt: snapshot.analysisCompletedAt,
            lastError: snapshot.lastError,
            currentJobId: snapshot.currentJobId,
            lastTestStatus: snapshot.lastTestStatus,
            lastUpdatedAt: Date()
        )
        taskActivityStore.ingestCodeReviewSnapshot(updatedSnapshot, conversationId: conversationId)
    }

    @MainActor
    func selectedCodeReviewSnapshot(sessionId: String) -> CodeReviewSessionSnapshot? {
        taskActivityStore.codeReviewSnapshot(
            sessionId: sessionId,
            conversationId: conversationId
        )
    }

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
