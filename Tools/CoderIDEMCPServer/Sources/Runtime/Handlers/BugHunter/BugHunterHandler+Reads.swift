import CoderEngine
import Foundation
import MCP

extension CoderIDEMCPServerApp {
    static func handleBugHunterStatus(args: [String: String]) -> CallTool.Result {
        if let bridged = rustBugHunterToolResult(name: "bughunter_status", args: args) {
            return bridged
        }
        guard let snapshot = resolveBugHunterSnapshot(args: args) else {
            return bugHunterOK("No BugHunter run found.")
        }
        let effectiveStatus = bugHunterEffectiveStatus(snapshot)
        var lines = [
            "run_id: \(snapshot.runId)",
            "status: \(effectiveStatus.rawValue)",
            "source_kind: \(snapshot.sourceKind.rawValue)",
            "trigger_kind: \(snapshot.triggerKind.rawValue)",
            "git_root: \(snapshot.gitRoot)",
        ]
        if let reviewSessionId = snapshot.reviewSessionId {
            lines.append("review_session_id: \(reviewSessionId)")
            if let reviewSnapshot = MCPSharedState.readCodeReviewSnapshot(sessionId: reviewSessionId) {
                let reviewStatus = VerifiedFindingsStatusService.payload(
                    snapshot: reviewSnapshot,
                    entryPoint: .mcp
                )
                lines.append("review_phase: \(reviewStatus["phase"] ?? "unknown")")
                lines.append("review_summary: \(reviewStatus["summary"] ?? "n/a")")
                lines.append("verified_findings: \(reviewStatus["verified_projection_findings"] ?? reviewStatus["findings_total"] ?? "0")")
                lines.append("candidate_queue: \(reviewStatus["verified_projection_candidates"] ?? reviewStatus["candidates_total"] ?? "0")")
                lines.append("duplicates: \(reviewStatus["verified_projection_duplicates"] ?? "0")")
                lines.append("stale_candidates: \(reviewStatus["verified_projection_stale_candidates"] ?? "0")")
                lines.append("security_gate_ready: \(reviewStatus["security_gate_ready"] ?? "false")")
                if let gateSummary = reviewStatus["security_gate_summary"] {
                    lines.append("security_gate_summary: \(gateSummary)")
                }
            }
            if let verifiedState = VerifiedFindingsService.resolve(
                sessionId: reviewSessionId,
                entryPoint: .mcp
            ) {
                lines.append("verified_envelope_source: \(verifiedState.recovered.source.rawValue)")
                lines.append("verified_replay_candidates: \(verifiedState.replayReport.candidateCount)")
                lines.append("verified_replay_findings: \(verifiedState.replayReport.verifiedCount)")
            }
        }
        if let branchName = snapshot.branchName { lines.append("branch: \(branchName)") }
        if let primaryCommit = snapshot.primaryCommit { lines.append("primary_commit: \(primaryCommit)") }
        if !snapshot.relatedCommits.isEmpty {
            lines.append("related_commits: \(snapshot.relatedCommits.joined(separator: ","))")
        }
        if let lastMessage = snapshot.lastMessage { lines.append("message: \(lastMessage)") }
        lines.append("verified_findings_count: \(snapshot.verifiedFindingsCount)")
        lines.append("candidate_findings_count: \(snapshot.candidateFindingsCount)")
        if let lastRevalidationVerdict = snapshot.lastRevalidationVerdict {
            lines.append("last_revalidation_verdict: \(lastRevalidationVerdict)")
        }
        if let securityGateReady = snapshot.securityGateReady {
            lines.append("security_gate_ready_cached: \(securityGateReady ? "true" : "false")")
        }
        if let pipelinePhase = snapshot.pipelinePhase {
            lines.append("pipeline_phase: \(pipelinePhase)")
        }
        if let progressPercent = snapshot.progressPercent {
            lines.append("progress_percent: \(progressPercent)")
        }
        if let stepsCompleted = snapshot.stepsCompleted, let stepsTotal = snapshot.stepsTotal {
            lines.append("steps_progress: \(stepsCompleted)/\(stepsTotal)")
        }
        if let toolsCompleted = snapshot.toolsCompleted, let toolsTotal = snapshot.toolsTotal {
            lines.append("tools_progress: \(toolsCompleted)/\(toolsTotal)")
        }
        if let toolsRunning = snapshot.toolsRunning {
            lines.append("tools_running: \(toolsRunning)")
        }
        if let verificationGateReady = snapshot.verificationGateReady {
            lines.append("verification_gate_ready: \(verificationGateReady ? "true" : "false")")
        }
        if let patchGateReady = snapshot.patchGateReady {
            lines.append("patch_gate_ready: \(patchGateReady ? "true" : "false")")
        }
        if let publishReady = snapshot.publishReady {
            lines.append("publish_ready: \(publishReady ? "true" : "false")")
        }
        if let bundleModes = snapshot.bundleModes, !bundleModes.isEmpty {
            lines.append("bundle_modes: \(bundleModes.joined(separator: ","))")
        }
        return bugHunterOK(lines.joined(separator: "\n"))
    }

    static func handleBugHunterFindings(args: [String: String]) -> CallTool.Result {
        if let bridged = rustBugHunterToolResult(name: "bughunter_findings", args: args) {
            return bridged
        }
        guard let snapshot = resolveBugHunterSnapshot(args: args),
              let reviewSessionId = snapshot.reviewSessionId,
              let reviewSnapshot = MCPSharedState.readCodeReviewSnapshot(sessionId: reviewSessionId) else {
            return bugHunterOK("No linked review findings available for this BugHunter run.")
        }
        let findings = BugHunterWorkflowService.findings(
            snapshot: reviewSnapshot,
            kind: args["kind"],
            severity: args["severity"],
            status: args["status"],
            limit: 50,
            includeSensitiveDetails: false,
            entryPoint: .mcp
        )
        if findings.isEmpty {
            return bugHunterOK("No BugHunter findings match the query.")
        }
        let lines = findings.enumerated().map { index, finding in
            let message = finding["message"] ?? finding["message_summary"] ?? "n/a"
            let file = finding["file_path"] ?? finding["file_label"] ?? "redacted"
            let line = finding["line_number"].map { ":\($0)" } ?? ""
            let domain = finding["domain"] ?? "bug"
            let duplicateOf = finding["possible_duplicate_of"].map { ", duplicate_of: \($0)" } ?? ""
            let staleStatus = finding["stale_status"].map { ", stale: \($0)" } ?? ""
            return "[\(index + 1)] [\(finding["severity"] ?? "?")] \(file)\(line) — \(message) (domain: \(domain), status: \(finding["status"] ?? "?")\(duplicateOf)\(staleStatus), id: \(finding["id"] ?? "?"))"
        }
        return bugHunterOK(lines.joined(separator: "\n"))
    }

    static func handleBugHunterRunHistory(args: [String: String]) -> CallTool.Result {
        if let bridged = rustBugHunterToolResult(name: "bughunter_run_history", args: args) {
            return bridged
        }
        let snapshots = MCPSharedState.readBugHunterSnapshots(
            conversationId: parseConversationId(args["conversation_id"])
        )
        guard !snapshots.isEmpty else { return bugHunterOK("No BugHunter runs found.") }
        let lines = snapshots.map { snapshot in
            "\(snapshot.runId) | \(bugHunterEffectiveStatus(snapshot).rawValue) | \(snapshot.sourceKind.rawValue) | review=\(snapshot.reviewSessionId ?? "n/a") | message=\(snapshot.lastMessage ?? "n/a")"
        }
        return bugHunterOK(lines.joined(separator: "\n"))
    }

    static func handleBugHunterExplainCluster(args: [String: String]) -> CallTool.Result {
        if let bridged = rustBugHunterToolResult(name: "bughunter_explain_cluster", args: args) {
            return bridged
        }
        guard let snapshot = resolveBugHunterSnapshot(args: args),
              let reviewSessionId = snapshot.reviewSessionId,
              let verifiedState = VerifiedFindingsService.resolve(
                sessionId: reviewSessionId,
                entryPoint: .mcp
              ) else {
            return bugHunterError("Error: unable to resolve BugHunter cluster context")
        }
        guard let cluster = BugHunterWorkflowService.explainCluster(
            resolved: verifiedState
        ) else {
            return bugHunterOK("No BugHunter cluster available.")
        }
        let lines = [
            "cluster_title: \(cluster.title)",
            "cluster_size: \(cluster.size)",
            "files: \(cluster.files.joined(separator: ", "))",
            String(format: "avg_confidence: %.2f", cluster.averageConfidence),
            "primary_risk: \(cluster.primaryRisk)",
        ]
        return bugHunterOK(lines.joined(separator: "\n"))
    }

    private static func resolveBugHunterSnapshot(
        args: [String: String]
    ) -> MCPSharedBugHunterSnapshot? {
        let runId = (args["run_id"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !runId.isEmpty {
            return MCPSharedState.readBugHunterSnapshot(runId: runId)
        }
        return MCPSharedState.readBugHunterSnapshots(
            conversationId: parseConversationId(args["conversation_id"])
        ).first
    }

    private static func bugHunterEffectiveStatus(
        _ snapshot: MCPSharedBugHunterSnapshot
    ) -> MCPSharedBugHunterRunStatus {
        guard let reviewSessionId = snapshot.reviewSessionId,
              let reviewSnapshot = MCPSharedState.readCodeReviewSnapshot(sessionId: reviewSessionId) else {
            return snapshot.status
        }
        switch reviewSnapshot.phase {
        case .completed:
            return .completed
        case .failed:
            return .failed
        case .analyzing, .fixing, .testing, .reReviewing:
            return .running
        case .idle:
            return snapshot.status
        }
    }
}
