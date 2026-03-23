import CoderEngine
import Foundation

extension SoloCodeApp {
    @MainActor
    func startBugHunterCommandLoopIfNeeded() {
        guard !didStartBugHunterCommandLoop else { return }
        didStartBugHunterCommandLoop = true

        let driver = BugHunterCommandLoopDriver(
            claimPendingCommands: {
                MCPSharedState.claimPendingBugHunterCommands()
            },
            claimHookEvents: {
                MCPSharedState.claimBugHunterHookEvents()
            }
        ) { [self] commands, hookEvents in
            await processClaimedBugHunterInputs(commands: commands, hookEvents: hookEvents)
        }

        Task.detached(priority: .utility) {
            await driver.run()
        }
    }

    @MainActor
    func processClaimedBugHunterInputs(
        commands: [MCPSharedBugHunterCommand],
        hookEvents: [MCPSharedBugHunterHookEvent]
    ) async {
        for event in hookEvents {
            await enqueueBugHunterFromHookEvent(event)
        }
        for command in commands {
            let outcome = await handleBugHunterCommand(command)
            MCPSharedState.markBugHunterCommand(
                id: command.id,
                status: outcome.success ? .completed : .failed,
                resultMessage: outcome.message
            )
        }
    }

    @MainActor
    func enqueueBugHunterPostCommit(
        commit: GitCommitResult,
        gitRoot: String,
        triggerKind: MCPSharedBugHunterTriggerKind
    ) {
        let settings = BugHunterSettingsPersistence.load()
        guard settings.enabled else { return }
        switch settings.triggerMode {
        case .appOnly, .appAndHook:
            break
        case .hookOnly:
            if triggerKind == .appCommit { return }
        }
        guard !hasRecentBugHunterRun(gitRoot: gitRoot, primaryCommit: commit.sha) else { return }

        let runId = "bughunter-\(commit.shortSha.lowercased())-\(String(UUID().uuidString.prefix(8)).lowercased())"
        let command = MCPSharedState.enqueueBugHunterCommand(
            action: "start",
            runId: runId,
            conversationId: nil,
            payload: [
                "source_kind": MCPSharedBugHunterSourceKind.commit.rawValue,
                "trigger_kind": triggerKind.rawValue,
                "git_root": gitRoot,
                "primary_commit": commit.sha,
                "branch_name": gitPanelStore.currentBranch,
            ]
        )
        MCPSharedState.writeBugHunterSnapshot(
            MCPSharedBugHunterSnapshot(
                runId: runId,
                sourceKind: .commit,
                triggerKind: triggerKind,
                gitRoot: gitRoot,
                branchName: gitPanelStore.currentBranch,
                primaryCommit: commit.sha,
                status: .queued,
                lastMessage: "Queued from commit \(commit.shortSha)",
                autoFixMode: settings.autofixMode.rawValue
            )
        )
        MCPSharedState.refreshBugHunterCommandHeartbeat(id: command.id)
    }

    @MainActor
    private func enqueueBugHunterFromHookEvent(_ event: MCPSharedBugHunterHookEvent) async {
        let settings = BugHunterSettingsPersistence.load()
        guard settings.enabled else { return }
        guard settings.triggerMode == .hookOnly || settings.triggerMode == .appAndHook else { return }
        guard !hasRecentBugHunterRun(gitRoot: event.gitRoot, primaryCommit: event.headSHA) else { return }
        let shortSHA = String(event.headSHA.prefix(8)).lowercased()
        let runId = "bughunter-hook-\(shortSHA)-\(String(UUID().uuidString.prefix(8)).lowercased())"
        _ = MCPSharedState.enqueueBugHunterCommand(
            action: "start",
            runId: runId,
            conversationId: nil,
            payload: [
                "source_kind": MCPSharedBugHunterSourceKind.commit.rawValue,
                "trigger_kind": MCPSharedBugHunterTriggerKind.gitHook.rawValue,
                "git_root": event.gitRoot,
                "primary_commit": event.headSHA,
            ]
        )
        MCPSharedState.writeBugHunterSnapshot(
            MCPSharedBugHunterSnapshot(
                runId: runId,
                sourceKind: .commit,
                triggerKind: .gitHook,
                gitRoot: event.gitRoot,
                primaryCommit: event.headSHA,
                status: .queued,
                lastMessage: "Queued from git hook \(shortSHA)",
                autoFixMode: settings.autofixMode.rawValue
            )
        )
    }

    @MainActor
    private func hasRecentBugHunterRun(gitRoot: String, primaryCommit: String) -> Bool {
        let now = Date()
        return MCPSharedState.readBugHunterSnapshots().contains { snapshot in
            guard snapshot.gitRoot == gitRoot, snapshot.primaryCommit == primaryCommit else { return false }
            guard now.timeIntervalSince(snapshot.lastUpdatedAt) < 1800 else { return false }
            return snapshot.status == .queued || snapshot.status == .running || snapshot.status == .awaitingApproval || snapshot.status == .completed
        }
    }
}
