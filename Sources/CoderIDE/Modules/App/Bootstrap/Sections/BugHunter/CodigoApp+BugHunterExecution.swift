import CoderEngine
import Foundation

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

        let reviewCommand: MCPSharedCodeReviewCommand
        do {
            reviewCommand = try MCPSharedState.enqueueUniqueCodeReviewStartCommand(
                sessionId: reviewSessionId,
                conversationId: nil,
                payload: [
                    "scope": promptAndCommits.2 == nil ? "uncommitted" : "against_ref",
                    "ref": promptAndCommits.2 ?? "",
                    "session_id": reviewSessionId,
                    "analysis_only": "false",
                    "max_rounds": String(max(3, settings.maxAutoRounds + 1)),
                    "max_workers": String(max(codeReviewPartitions, 4)),
                    "bughunter_run_id": command.runId,
                    "bughunter_profile": sourceKind == .commit ? BugHunterProfile.commitReview.rawValue : BugHunterProfile.deep.rawValue,
                    "bughunter_prompt_override": promptAndCommits.0,
                ]
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
            primaryCommit: promptAndCommits.2,
            relatedCommits: promptAndCommits.1.filter { !$0.isEmpty && $0 != promptAndCommits.2 },
            status: .running,
            startedAt: Date(),
            lastMessage: "BugHunter run started",
            autoFixMode: settings.autofixMode.rawValue
        )
        MCPSharedState.writeBugHunterSnapshot(snapshot)
        await processPendingCodeReviewCommandsOnce()
        MCPSharedState.refreshCodeReviewCommandHeartbeat(id: reviewCommand.id)
        return (true, "BugHunter run \(command.runId) started")
    }

    @MainActor
    private func executeBugHunterAutofix(
        _ command: MCPSharedBugHunterCommand,
        mode: BugHunterAutofixExecutionMode
    ) async -> (success: Bool, message: String) {
        guard let snapshot = MCPSharedState.readBugHunterSnapshot(runId: command.runId),
              let reviewSessionId = snapshot.reviewSessionId else {
            return (false, "BugHunter run not found")
        }
        guard let reviewSnapshot = resolveCodeReviewSnapshot(sessionId: reviewSessionId, conversationId: nil) else {
            return (false, "Linked review session not found")
        }

        let autofixable = reviewSnapshot.findings
            .filter { ($0.confidence ?? 0) >= 0.9 && $0.patchArtifactId != nil }
            .sorted { ($0.confidence ?? 0) > ($1.confidence ?? 0) }

        guard let finding = autofixable.first else {
            return (false, "No autofixable verified bug found")
        }

        let patchCommandAction: String = switch mode {
        case .preview: "prepare_patch"
        case .apply: "apply_patch"
        case .commit: "apply_patch"
        }

        let patchCommand = MCPSharedState.enqueueCodeReviewCommand(
            action: patchCommandAction,
            sessionId: reviewSessionId,
            conversationId: nil,
            payload: [
                "session_id": reviewSessionId,
                "finding_id": finding.id,
            ]
        )
        await processPendingCodeReviewCommandsOnce()
        MCPSharedState.refreshCodeReviewCommandHeartbeat(id: patchCommand.id)

        if mode == .commit {
            let gitRoot = workspaceStore.activeWorkspacePaths.first?.path ?? snapshot.gitRoot
            guard !gitRoot.isEmpty else { return (false, "Missing git root for autofix commit") }
            do {
                let commit = try GitService().commit(
                    gitRoot: gitRoot,
                    message: "fix(bughunter): \(finding.filePath.components(separatedBy: "/").last ?? finding.filePath)",
                    includeUnstaged: false
                )
                enqueueBugHunterPostCommit(commit: commit, gitRoot: gitRoot, triggerKind: .manual)
                let updated = MCPSharedBugHunterSnapshot(
                    runId: snapshot.runId,
                    conversationId: snapshot.conversationId,
                    reviewSessionId: snapshot.reviewSessionId,
                    sourceKind: .autofixRound,
                    triggerKind: snapshot.triggerKind,
                    gitRoot: snapshot.gitRoot,
                    branchName: snapshot.branchName,
                    primaryCommit: commit.sha,
                    relatedCommits: snapshot.relatedCommits,
                    status: .completed,
                    startedAt: snapshot.startedAt,
                    completedAt: Date(),
                    lastUpdatedAt: Date(),
                    lastMessage: "Autofix commit \(commit.shortSha) created",
                    autoFixMode: snapshot.autoFixMode,
                    cleanAfterFix: false
                )
                MCPSharedState.writeBugHunterSnapshot(updated)
                return (true, "Autofix commit \(commit.shortSha) created")
            } catch {
                return (false, error.localizedDescription)
            }
        }

        return (true, mode == .preview ? "Autofix preview prepared" : "Autofix applied")
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

private enum BugHunterAutofixExecutionMode {
    case preview
    case apply
    case commit
}
