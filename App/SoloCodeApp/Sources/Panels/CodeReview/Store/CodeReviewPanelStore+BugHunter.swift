import CoderEngine
import Foundation

extension CodeReviewPanelStore {
    func startBugHunterUncommitted() {
        guard let gitRoot = workspaceStore.activeWorkspacePaths.first?.path else { return }
        let runId = "bughunter-panel-\(UUID().uuidString.lowercased())"
        _ = MCPSharedState.enqueueBugHunterCommand(
            action: "start",
            runId: runId,
            conversationId: conversationId,
            payload: [
                "source_kind": MCPSharedBugHunterSourceKind.uncommitted.rawValue,
                "trigger_kind": MCPSharedBugHunterTriggerKind.manual.rawValue,
                "git_root": gitRoot,
            ]
        )
        MCPSharedState.writeBugHunterSnapshot(
            MCPSharedBugHunterSnapshot(
                runId: runId,
                conversationId: conversationId?.uuidString.lowercased(),
                sourceKind: .uncommitted,
                triggerKind: .manual,
                gitRoot: gitRoot,
                branchName: currentGitBranch,
                status: .queued,
                lastMessage: "Queued from review panel",
                autoFixMode: bugHunterSettings.autofixMode.rawValue,
                pipelinePhase: "queued",
                progressPercent: 0,
                stepsTotal: 6,
                stepsCompleted: 0,
                toolsTotal: 3,
                toolsCompleted: 0,
                toolsRunning: 0,
                verificationGateReady: false,
                patchGateReady: false,
                bundleModes: ["standard", "bugFinder", "securityAudit"],
                publishReady: false
            )
        )
        appendPanelSystemMessage(
            "BugHunter queued on uncommitted changes.",
            kind: .statusNote,
            selectChatTab: true
        )
    }

    func startBugHunterCommitWindow() {
        guard let primaryCommit = selectedCommits.first ?? gitCommitLog.first?.sha,
              let gitRoot = workspaceStore.activeWorkspacePaths.first?.path else { return }
        let runId = "bughunter-window-\(UUID().uuidString.lowercased())"
        _ = MCPSharedState.enqueueBugHunterCommand(
            action: "start",
            runId: runId,
            conversationId: conversationId,
            payload: [
                "source_kind": MCPSharedBugHunterSourceKind.commitWindow.rawValue,
                "trigger_kind": MCPSharedBugHunterTriggerKind.manual.rawValue,
                "git_root": gitRoot,
                "primary_commit": primaryCommit,
                "branch_name": currentGitBranch,
            ]
        )
        appendPanelSystemMessage(
            "BugHunter queued on commit window \(primaryCommit.prefix(8)).",
            kind: .statusNote,
            selectChatTab: true
        )
    }
}
