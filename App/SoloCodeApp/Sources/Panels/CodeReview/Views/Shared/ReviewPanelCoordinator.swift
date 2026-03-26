import CoderEngine
import Foundation

struct ReviewPanelReviewTaskResult {
    let snapshot: CodeReviewSessionSnapshot
    let error: String?
    let wasCancelled: Bool
}

/// Lightweight coordinator that owns running review Tasks.
/// All state flows back through `CodeReviewSessionState.onStateChange`.
@MainActor
final class ReviewPanelCoordinator {

    // MARK: - Task State

    private(set) var reviewTask: Task<Void, Never>?
    private(set) var isReviewRunning: Bool = false

    // MARK: - Review Execution

    /// Runs a code review using the multi-swarm provider.
    /// Replicates the pattern from `SoloCodeApp.launchDeferredReviewCommand`.
    func runReview(
        provider: any LLMProvider,
        prompt: String,
        context: WorkspaceContext,
        sessionState: CodeReviewSessionState,
        onEvent: @escaping @MainActor (StreamEvent) -> Void,
        onStart: @escaping @MainActor () -> Void,
        onFinish: @escaping @MainActor (ReviewPanelReviewTaskResult) -> Void
    ) {
        cancelReview()
        isReviewRunning = true

        reviewTask = Task.detached(priority: .userInitiated) { [weak self] in
            await MainActor.run { onStart() }
            var streamError: String?
            do {
                let stream = try await provider.send(
                    prompt: prompt,
                    context: context,
                    imageURLs: nil
                )
                for try await event in stream {
                    if Task.isCancelled { break }
                    await MainActor.run { onEvent(event) }
                }
            } catch {
                if !Task.isCancelled {
                    await sessionState.fail(error: error.localizedDescription)
                    streamError = error.localizedDescription
                }
            }
            if Task.isCancelled {
                let snap = await sessionState.snapshot()
                if snap.phase.isActive {
                    await sessionState.fail(error: "Review cancelled.")
                }
            }
            let snapshot = await sessionState.snapshot()
            let reviewError = streamError
            let reviewCancelled = Task.isCancelled
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isReviewRunning = false
                onFinish(
                    ReviewPanelReviewTaskResult(
                        snapshot: snapshot,
                        error: reviewError,
                        wasCancelled: reviewCancelled
                    )
                )
            }
        }
    }

    func cancelReview() {
        reviewTask?.cancel()
        reviewTask = nil
        isReviewRunning = false
    }

}

extension CodeReviewPanelStore {
    func formattedReviewRunEvent(
        type: String,
        payload: [String: String]
    ) -> (sectionTitle: String, line: String)? {
        switch type {
        case "reasoning":
            if let detail = firstNonEmpty([payload["detail"], payload["text"], payload["delta"], payload["content"], payload["summary"]]) { return ("Thinking", detail) }
        case "assistant_update":
            if let detail = firstNonEmpty([payload["output"], payload["content"], payload["text"], payload["detail"], payload["summary"]]) { return ("Response", detail) }
        case "review-worker-plan":
            let description = firstNonEmpty([payload["description"], payload["title"]]) ?? "Planned worker"
            let severity = payload["severity"].map { "[\($0)] " } ?? ""
            let fileCount = payload["fileCount"].map { " (\($0) files)" } ?? ""
            return ("Planned Work", "- [ ] \(severity)\(description)\(fileCount)")
        case "review-fix-round":
            return ("Progress", "Round \(payload["round"] ?? "?")/\(payload["maxRounds"] ?? "?")")
        case "review-audit-tool":
            return ("Audit", "\(payload["tool"] ?? "audit"): \(payload["detail"] ?? "completed")")
        case "agent":
            return ("Activity", "\(payload["title"] ?? payload["agent_name"] ?? "agent") — \(payload["detail"] ?? payload["status"] ?? "updated")")
        case "tool_execution_error", "tool_validation_error":
            return ("Activity", "Error: \(payload["detail"] ?? payload["title"] ?? "Tool error")")
        default:
            if let detail = firstNonEmpty([payload["detail"], payload["title"], payload["summary"], payload["status"], payload["tool"], payload["type"]]) {
                return ("Activity", "\(type): \(detail)")
            }
            return ("Activity", type)
        }
        return nil
    }

    func enrichedReviewRawPayload(type: String, payload: [String: String]) -> [String: String] {
        var enriched = payload
        switch type {
        case "review-worker-plan":
            if let workerId = firstNonEmpty([payload["worker_id"], payload["id"]]) {
                enriched["swarm_id"] = workerId
                enriched["group_id"] = payload["group_id"] ?? "swarm-\(workerId)"
                enriched["agent_name"] = payload["agent_name"] ?? workerId
                enriched["title"] = payload["title"] ?? payload["description"] ?? workerId
                if enriched["detail"] == nil { enriched["detail"] = "planned" }
            }
        case "review-audit-tool":
            if let tool = firstNonEmpty([payload["tool"]]) {
                let swarmId = "audit-\(tool)"
                enriched["swarm_id"] = swarmId
                enriched["group_id"] = payload["group_id"] ?? "swarm-\(swarmId)"
                enriched["agent_name"] = payload["agent_name"] ?? tool
                enriched["title"] = payload["title"] ?? tool
            }
        case "agent":
            if let swarmId = firstNonEmpty([payload["swarm_id"], payload["swarmId"]]) {
                enriched["group_id"] = payload["group_id"] ?? "swarm-\(swarmId)"
                enriched["agent_name"] = payload["agent_name"] ?? payload["title"] ?? swarmId
            }
        default:
            break
        }
        return enriched
    }

    func scopedTaskActivity(_ activity: TaskActivity) -> TaskActivity {
        guard let conversationId else { return activity }
        var payload = activity.payload
        payload["conversation_id"] = conversationId.uuidString.lowercased()
        return TaskActivity(
            id: activity.id,
            type: activity.type,
            title: activity.title,
            detail: activity.detail,
            payload: payload,
            timestamp: activity.timestamp,
            phase: activity.phase,
            isRunning: activity.isRunning,
            groupId: activity.groupId
        )
    }
}

extension ReviewPanelCoordinator {
    static func combinedPrompt(scope: ReviewScopeTarget, currentBranch: String, selectedModes: Set<CodeReviewPanelMode>, customInstructions: String = "") -> String {
        rustPrompt(kind: "combined", scope: scope, currentBranch: currentBranch, selectedModes: selectedModes, customInstructions: customInstructions)
    }
    static func standardPrompt(scope: ReviewScopeTarget, customInstructions: String = "") -> String { rustPrompt(kind: "standard", scope: scope, customInstructions: customInstructions) }
    static func securityAuditPrompt(scope: ReviewScopeTarget) -> String { rustPrompt(kind: "security_audit", scope: scope) }
    static func bugFinderPrompt(scope: ReviewScopeTarget) -> String { rustPrompt(kind: "bug_finder", scope: scope) }
    static func branchReviewPrompt(branch: String, currentBranch: String) -> String { rustPrompt(kind: "branch_review", scope: .branch(branch), currentBranch: currentBranch) }
    static func commitRangePrompt(commits: [String]) -> String { rustPrompt(kind: "commit_range", scope: .commits(commits)) }
    static func chatContextPrompt(userMessage: String, sessionSummary: String, findingsCount: Int, openCount: Int, activeSessionId: String?, conversationId: UUID?) -> String {
        rustPrompt(kind: "chat_context", userMessage: userMessage, sessionSummary: sessionSummary, findingsCount: findingsCount, openCount: openCount, activeSessionId: activeSessionId, conversationId: conversationId)
    }

    private static func rustPrompt(
        kind: String,
        scope: ReviewScopeTarget = .uncommitted,
        currentBranch: String? = nil,
        selectedModes: Set<CodeReviewPanelMode> = [],
        customInstructions: String = "",
        userMessage: String? = nil,
        sessionSummary: String? = nil,
        findingsCount: Int? = nil,
        openCount: Int? = nil,
        activeSessionId: String? = nil,
        conversationId: UUID? = nil
    ) -> String {
        let request = ReviewPanelPromptBridgeRequest(
            schemaVersion: 1,
            promptKind: kind,
            scopeTag: scope.scopeTag,
            scopeKind: scope.bridgeKind,
            currentBranch: currentBranch,
            branchName: scope.branchName,
            commits: scope.commits,
            selectedModes: CodeReviewPanelMode.allCases.filter { selectedModes.contains($0) }.map(\.bridgeName),
            customInstructions: customInstructions.isEmpty ? nil : customInstructions,
            userMessage: userMessage,
            sessionSummary: sessionSummary,
            findingsCount: findingsCount,
            openCount: openCount,
            activeSessionId: activeSessionId,
            conversationId: conversationId?.uuidString
        )
        return ReviewCommandRustBridge.buildPanelPrompt(request)
            ?? "Rust review panel prompt runtime required."
    }
}

private extension ReviewScopeTarget {
    var bridgeKind: String {
        switch self {
        case .branch: return "branch"
        case .commits: return "commits"
        case .againstRef: return "against_ref"
        case .staged: return "staged"
        case .workspace: return "workspace"
        case .uncommitted: return "uncommitted"
        }
    }

    var branchName: String? { if case .branch(let name) = self { return name }; return nil }
    var commits: [String] { if case .commits(let shas) = self { return shas }; return [] }
}

private extension CodeReviewPanelMode {
    var bridgeName: String {
        switch self {
        case .standard: return "standard"
        case .securityAudit: return "securityAudit"
        case .bugFinder: return "bugFinder"
        }
    }
}
