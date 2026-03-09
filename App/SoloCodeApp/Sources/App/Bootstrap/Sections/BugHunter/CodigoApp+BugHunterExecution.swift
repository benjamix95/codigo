import CoderEngine
import Foundation

enum BugHunterRunIdentityResolver {
    static func canonicalPrimaryCommit(
        sourceKind: MCPSharedBugHunterSourceKind,
        payloadPrimaryCommit: String?,
        resolvedPrimaryCommit: String?
    ) -> String? {
        switch sourceKind {
        case .commit, .commitWindow, .autofixRound:
            let explicit = (payloadPrimaryCommit ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !explicit.isEmpty { return explicit }
            let resolved = (resolvedPrimaryCommit ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return resolved.isEmpty ? nil : resolved
        case .branchWindow, .uncommitted:
            return nil
        }
    }
}

extension CodigoApp {
    @MainActor
    func handleBugHunterCommand(
        _ command: MCPSharedBugHunterCommand
    ) async -> (success: Bool, message: String) {
        switch command.action {
        case "start":
            return await startBugHunterRun(command)
        case "autofix_preview":
            return await executeBugHunterAutofix(command, mode: .preview)
        case "autofix_apply":
            return await executeBugHunterAutofix(command, mode: .apply)
        case "autofix_commit":
            return await executeBugHunterAutofix(command, mode: .commit)
        case "cancel_run":
            return await cancelBugHunterRun(command)
        case "install_hook":
            return await configureBugHunterHook(command, install: true)
        case "uninstall_hook":
            return await configureBugHunterHook(command, install: false)
        default:
            return (false, "Unsupported bugHunter command: \(command.action)")
        }
    }

    @MainActor
    private func startBugHunterRun(
        _ command: MCPSharedBugHunterCommand
    ) async -> (success: Bool, message: String) {
        let settings = BugHunterSettingsPersistence.load()
        let gitRoot = (command.payload["git_root"] ?? workspaceStore.activeWorkspacePaths.first?.path ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !gitRoot.isEmpty else {
            return (false, "Missing git_root for bugHunter run")
        }

        let scopeResolver = BugHunterScopeResolver()
        let sourceKind = MCPSharedBugHunterSourceKind(rawValue: command.payload["source_kind"] ?? "") ?? .uncommitted
        let reviewSessionId = "bughunter-review-\(command.runId)"

        let promptAndCommits: (String, [String], String?) = {
            switch sourceKind {
            case .commit, .commitWindow:
                let primaryCommit = command.payload["primary_commit"] ?? ""
                let window = (try? scopeResolver.correlatedCommitWindow(
                    gitRoot: gitRoot,
                    primaryCommit: primaryCommit,
                    maxCount: settings.maxCommitWindow
                )) ?? BugHunterCommitWindow(primaryCommit: primaryCommit, relatedCommits: [], files: [])
                let prompt = BugHunterPromptBuilder.prompt(
                    scopeTag: "[AGAINST:\(scopeResolver.againstRefExpression(for: window))]",
                    profile: .commitWindow,
                    commitWindow: window,
                    autoFixMode: settings.autofixMode,
                    maxAutoRounds: settings.maxAutoRounds
                )
                return (prompt, [primaryCommit] + window.relatedCommits, scopeResolver.againstRefExpression(for: window))
            case .branchWindow:
                let branch = command.payload["branch_name"] ?? gitPanelStore.currentBranch
                let prompt = BugHunterPromptBuilder.prompt(
                    scopeTag: "[AGAINST:\(branch)]",
                    profile: .regressionGuard,
                    autoFixMode: settings.autofixMode,
                    maxAutoRounds: settings.maxAutoRounds
                )
                return (prompt, [], branch)
            case .autofixRound, .uncommitted:
                let prompt = BugHunterPromptBuilder.prompt(
                    scopeTag: "[REVIEW_SCOPE:uncommitted]",
                    profile: sourceKind == .autofixRound ? .autofixRound : .deep,
                    autoFixMode: settings.autofixMode,
                    maxAutoRounds: settings.maxAutoRounds
                )
                return (prompt, [], nil)
            }
        }()
        let canonicalPrimaryCommit = BugHunterRunIdentityResolver.canonicalPrimaryCommit(
            sourceKind: sourceKind,
            payloadPrimaryCommit: command.payload["primary_commit"],
            resolvedPrimaryCommit: promptAndCommits.1.first
        )

        let reviewCommand: MCPSharedCodeReviewCommand
        do {
            let request = try BugHunterWorkflowService.makeStartRequest(
                runId: command.runId,
                reviewSessionId: reviewSessionId,
                sourceKind: sourceKind,
                againstRef: promptAndCommits.2,
                prompt: promptAndCommits.0,
                maxRounds: max(3, settings.maxAutoRounds + 1),
                maxWorkers: max(codeReviewPartitions, 4),
                conversationId: nil
            )
            reviewCommand = try VerifiedFindingsStartCommandService.enqueueReviewStart(
                request: request
            )
        } catch {
            return (false, error.localizedDescription)
        }

        let snapshot = MCPSharedBugHunterSnapshot(
            runId: command.runId,
            reviewSessionId: reviewSessionId,
            sourceKind: sourceKind,
            triggerKind: MCPSharedBugHunterTriggerKind(rawValue: command.payload["trigger_kind"] ?? "") ?? .manual,
            gitRoot: gitRoot,
            branchName: command.payload["branch_name"] ?? gitPanelStore.currentBranch,
            primaryCommit: canonicalPrimaryCommit,
            relatedCommits: promptAndCommits.1.filter { !$0.isEmpty && $0 != canonicalPrimaryCommit },
            status: .running,
            startedAt: Date(),
            lastMessage: "BugHunter run started",
            autoFixMode: settings.autofixMode.rawValue,
            verifiedFindingsCount: 0,
            candidateFindingsCount: 0,
            lastRevalidationVerdict: nil,
            securityGateReady: nil
        )
        MCPSharedState.writeBugHunterSnapshot(snapshot)
        await processPendingCodeReviewCommandsOnce()
        MCPSharedState.refreshCodeReviewCommandHeartbeat(id: reviewCommand.id)
        await refreshBugHunterSnapshotFromReview(runId: command.runId)
        return (true, "BugHunter run \(command.runId) started")
    }

    @MainActor
    private func configureBugHunterHook(
        _ command: MCPSharedBugHunterCommand,
        install: Bool
    ) async -> (success: Bool, message: String) {
        let gitRoot = (command.payload["git_root"] ?? workspaceStore.activeWorkspacePaths.first?.path ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !gitRoot.isEmpty else { return (false, "Missing git_root") }
        let hookService = BugHunterHookService()
        do {
            if install {
                try hookService.installPostCommitHook(gitRoot: gitRoot)
            } else {
                try hookService.uninstallPostCommitHook(gitRoot: gitRoot)
            }
            var settings = BugHunterSettingsPersistence.load()
            settings.installGitHook = install
            BugHunterSettingsPersistence.save(settings)
            return (true, install ? "BugHunter post-commit hook installed" : "BugHunter post-commit hook removed")
        } catch {
            return (false, error.localizedDescription)
        }
    }
}

enum BugHunterAutofixExecutionMode {
    case preview
    case apply
    case commit
}
