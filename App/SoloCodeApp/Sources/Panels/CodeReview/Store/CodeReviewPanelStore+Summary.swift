import CoderEngine
import Foundation

extension CodeReviewPanelStore {
    func exportSummary(sessionId: String) -> String {
        guard let snapshot = taskActivityStore.codeReviewSnapshot(
            sessionId: sessionId,
            conversationId: conversationId
        ) else { return "No session found" }
        return ReviewPanelChatMessageFactory.summary(snapshot: snapshot).content
    }

    func publishSummaryToChat(sessionId: String) {
        guard settings.publishOutcomeToChat else { return }
        guard let snapshot = taskActivityStore.codeReviewSnapshot(
            sessionId: sessionId,
            conversationId: conversationId
        ) else { return }
        selectTab(.chat)
        appendChatMessage(ReviewPanelChatMessageFactory.summary(snapshot: snapshot))
    }

    var currentReviewPanelDerivedState: ReviewPanelDerivedState? {
        taskActivityStore.reviewPanelDerivedState(
            sessionId: selectedSessionId,
            conversationId: conversationId
        )
    }

    var currentReviewPanelWarmState: ReviewPanelWarmState {
        if let derivedState = currentReviewPanelDerivedState,
           derivedState.sessionId == currentSnapshot?.sessionId,
           derivedState.mutationSequence == currentSnapshot?.mutationSequence {
            return derivedState.warmState
        }
        return currentSnapshot == nil ? .idle : .warming
    }

    var currentPipelineJobState: ReviewPipelineJobState? {
        currentReviewPanelDerivedState?.pipelineJobState
    }

    var currentPublishedFindings: [CodeReviewFinding] {
        currentReviewPanelDerivedState?.publishedFindings ?? []
    }
}

enum ReviewPipelineJobStateBuilder {
    static func build(
        snapshot: CodeReviewSessionSnapshot,
        entryPoint: VerifiedFindingOriginEntryPoint = .panel
    ) -> ReviewPipelineJobState {
        let pipeline = VerifiedFindingsPipelineStatusService.evaluate(
            snapshot: snapshot,
            entryPoint: entryPoint
        )
        let bundleModes = pipeline.bundleModes.isEmpty ? ["standard", "bugFinder", "securityAudit"] : pipeline.bundleModes

        return ReviewPipelineJobState(
            title: "Unified Review Pipeline",
            phase: pipeline.pipelinePhase,
            progressPercent: pipeline.progressPercent,
            stepsCompleted: pipeline.stepsCompleted,
            stepsTotal: pipeline.stepsTotal,
            toolsTotal: pipeline.toolsTotal,
            toolsCompleted: pipeline.toolsCompleted,
            toolsRunning: pipeline.toolsRunning,
            candidateCount: pipeline.candidateCount,
            verifiedCount: pipeline.verifiedCount,
            publishedFindingCount: pipeline.publishedFindingCount,
            hiddenFindingCount: max(snapshot.findings.count - pipeline.publishedFindingCount, 0),
            gates: [
                ReviewPipelineGateState(title: "Verification", isReady: pipeline.verificationGateReady),
                ReviewPipelineGateState(title: "Patch", isReady: pipeline.patchGateReady),
            ],
            tools: toolExecutions(
                audit: snapshot.audit,
                pipeline: pipeline,
                bundleModes: bundleModes
            ),
            bundleModes: bundleModes,
            isTerminal: snapshot.phase == .completed || snapshot.phase == .failed
        )
    }

    private static func toolExecutions(
        audit: ReviewAuditSnapshot,
        pipeline: VerifiedFindingsPipelineStatus,
        bundleModes: [String]
    ) -> [ReviewPipelineToolExecution] {
        let auditedTools = audit.toolCoverage.keys.sorted().map { toolName in
            ReviewPipelineToolExecution(
                id: toolName,
                title: displayTitle(for: toolName),
                status: .completed,
                findingsCount: audit.toolFindingsCounts[toolName] ?? 0
            )
        }
        if !auditedTools.isEmpty {
            return auditedTools
        }

        return bundleModes.enumerated().map { index, mode in
            let runningThreshold = min(pipeline.toolsRunning, bundleModes.count)
            let status: ReviewPipelineToolExecution.Status
            if index < pipeline.toolsCompleted {
                status = .completed
            } else if index < pipeline.toolsCompleted + runningThreshold {
                status = .running
            } else {
                status = .pending
            }
            return ReviewPipelineToolExecution(
                id: mode,
                title: displayTitle(for: mode),
                status: status,
                findingsCount: 0
            )
        }
    }

    static func displayTitle(for rawValue: String) -> String {
        switch rawValue {
        case "standard": return "Standard Review"
        case "bugFinder": return "Bug Finder"
        case "securityAudit": return "Security Audit"
        default:
            return rawValue
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")
                .capitalized
        }
    }
}

enum ReviewPanelDerivedStateBuilder {
    private static let cacheLock = NSLock()
    private static var cache: [String: ReviewPanelDerivedState] = [:]

    static func build(
        snapshot: CodeReviewSessionSnapshot,
        existingEnvelope: VerifiedFindingsSessionEnvelope?
    ) -> ReviewPanelDerivedState {
        let cacheKey = "\(snapshot.sessionId)#\(snapshot.mutationSequence)"
        cacheLock.lock()
        if let cached = cache[cacheKey] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()

        let fallbackEnvelope = existingEnvelope
            ?? persistedEnvelopeFallback(for: snapshot)
        let verifiedEnvelope = snapshot.verifiedFindings
            ?? VerifiedFindingsSessionSyncService.sync(
                snapshot: snapshot,
                existingEnvelope: fallbackEnvelope,
                entryPoint: .panel
            )
        let effectiveSnapshot = snapshot.copying(
            mutationSequence: snapshot.mutationSequence,
            verifiedFindings: verifiedEnvelope,
            lastUpdatedAt: snapshot.lastUpdatedAt
        )
        let rustPanelState = ReviewPanelStateRustAdapter.reduce(snapshot: effectiveSnapshot)
        let publishedFindingIDs = rustPanelState?.publishedFindingIds
            ?? publishedFindingIDsFallback(snapshot: effectiveSnapshot)
        let findingsById = Dictionary(uniqueKeysWithValues: effectiveSnapshot.findings.map { ($0.id, $0) })
        let publishedFindings = publishedFindingIDs.compactMap { findingsById[$0] }
        let pipelineJobState = rustPanelState?.makePipelineJobState()
            ?? ReviewPipelineJobStateBuilder.build(
                snapshot: effectiveSnapshot,
                entryPoint: .panel
            )
        let publishedSeverityCounts = rustPanelState?.publishedSeverityCounts.findingSeverityCounts
            ?? Dictionary(grouping: publishedFindings, by: \.severity).reduce(into: [FindingSeverity: Int]()) { partialResult, entry in
                partialResult[entry.key] = entry.value.count
            }
        let emptyStateTitle = rustPanelState?.emptyStateTitle
            ?? fallbackEmptyStateTitle(snapshot: effectiveSnapshot, pipeline: pipelineJobState)
        let emptyStateSubtitle = rustPanelState?.emptyStateSubtitle
            ?? fallbackEmptyStateSubtitle(snapshot: effectiveSnapshot, pipeline: pipelineJobState)

        let derivedState = ReviewPanelDerivedState(
            sessionId: effectiveSnapshot.sessionId,
            mutationSequence: effectiveSnapshot.mutationSequence,
            publishedFindings: publishedFindings,
            publishedSeverityCounts: publishedSeverityCounts,
            pipelineJobState: pipelineJobState,
            projection: verifiedEnvelope.projectionSnapshot,
            verifiedEnvelope: verifiedEnvelope,
            warmState: rustPanelState?.warmState.reviewPanelWarmState ?? .ready,
            emptyStateTitle: emptyStateTitle,
            emptyStateSubtitle: emptyStateSubtitle
        )

        cacheLock.lock()
        cache[cacheKey] = derivedState
        cacheLock.unlock()
        return derivedState
    }

    static func invalidate(sessionId: String) {
        cacheLock.lock()
        cache = cache.filter { key, _ in
            !key.hasPrefix("\(sessionId)#")
        }
        cacheLock.unlock()
    }

    private static func persistedEnvelopeFallback(
        for snapshot: CodeReviewSessionSnapshot
    ) -> VerifiedFindingsSessionEnvelope? {
        guard snapshot.verifiedFindings == nil else { return nil }
        guard snapshot.phase == .completed || snapshot.phase == .failed else { return nil }
        return MCPSharedState.readVerifiedFindingsEnvelope(sessionId: snapshot.sessionId)
    }

    private static func publishedFindingIDsFallback(
        snapshot: CodeReviewSessionSnapshot
    ) -> [String] {
        guard let envelope = snapshot.verifiedFindings else { return [] }
        let verifiedIds = Set(envelope.projectionSnapshot.verifiedQueue.map(\.id))
        let patchesByFindingId = Dictionary(
            uniqueKeysWithValues: snapshot.patches.map { ($0.findingId, $0) }
        )

        let published: [String] = snapshot.findings.compactMap { finding -> String? in
            guard verifiedIds.contains(finding.id) else { return nil }
            let isVerified = finding.verifiedAt != nil || finding.verificationReport != nil
            guard isVerified,
                  let patchId = finding.patchArtifactId,
                  let patch = patchesByFindingId[finding.id],
                  patch.id == patchId else {
                return nil
            }
            guard patch.verifyStatus == .verified,
                  [.verified, .applied, .prOpened, .merged].contains(patch.status) else {
                return nil
            }
            return finding.id
        }
        let findingsById = Dictionary(uniqueKeysWithValues: snapshot.findings.map { ($0.id, $0) })
        return published.sorted { lhs, rhs in
            guard let left = findingsById[lhs], let right = findingsById[rhs] else { return lhs < rhs }
            if left.severity.sortOrder != right.severity.sortOrder {
                return left.severity.sortOrder < right.severity.sortOrder
            }
            if left.filePath != right.filePath {
                return left.filePath < right.filePath
            }
            return (left.lineNumber ?? 0) < (right.lineNumber ?? 0)
        }
    }

    private static func fallbackEmptyStateTitle(
        snapshot: CodeReviewSessionSnapshot,
        pipeline: ReviewPipelineJobState?
    ) -> String {
        pipeline == nil ? "No findings yet" : "No published findings yet"
    }

    private static func fallbackEmptyStateSubtitle(
        snapshot: CodeReviewSessionSnapshot,
        pipeline: ReviewPipelineJobState?
    ) -> String {
        if let pipeline {
            if pipeline.hiddenFindingCount > 0 {
                return "Verification and patch preparation are still gating the findings."
            }
            if pipeline.isTerminal {
                return "The run completed without any publish-ready findings."
            }
            return "The pipeline is still running. Findings appear only after verification and patch preview."
        }
        return "Start a review to analyze your code"
    }
}

private enum ReviewPanelStateRustAdapter {
    static func reduce(
        snapshot: CodeReviewSessionSnapshot
    ) -> ReviewPanelRustPanelState? {
        let response: ReviewPanelReduceResponse? = ReviewCoreBridge.call(
            functionName: "review_core_reduce_panel_state",
            request: ReviewPanelReduceRequest(snapshot: snapshot)
        )
        guard response?.error == nil else { return nil }
        return response?.panelState
    }
}

private struct ReviewPanelReduceRequest: Encodable {
    let schemaVersion: Int = 1
    let operation: String = "derive_review_panel_state"
    let snapshot: CodeReviewSessionSnapshot
}

private struct ReviewPanelReduceResponse: Decodable {
    let schemaVersion: Int
    let error: ReviewPanelReduceError?
    let panelState: ReviewPanelRustPanelState?
}

private struct ReviewPanelReduceError: Decodable {
    let code: String
    let message: String
}

private struct ReviewPanelRustPanelState: Decodable {
    let publishedFindingIds: [String]
    let publishedSeverityCounts: [String: Int]
    let pipelinePhase: String
    let progressPercent: Int
    let stepsCompleted: Int
    let stepsTotal: Int
    let toolsTotal: Int
    let toolsCompleted: Int
    let toolsRunning: Int
    let candidateCount: Int
    let verifiedCount: Int
    let publishedFindingCount: Int
    let hiddenFindingCount: Int
    let verificationGateReady: Bool
    let patchGateReady: Bool
    let bundleModes: [String]
    let toolExecutions: [ReviewPanelRustToolExecution]
    let isTerminal: Bool
    let warmState: String
    let emptyStateTitle: String
    let emptyStateSubtitle: String

    func makePipelineJobState() -> ReviewPipelineJobState {
        ReviewPipelineJobState(
            title: "Unified Review Pipeline",
            phase: pipelinePhase,
            progressPercent: progressPercent,
            stepsCompleted: stepsCompleted,
            stepsTotal: stepsTotal,
            toolsTotal: toolsTotal,
            toolsCompleted: toolsCompleted,
            toolsRunning: toolsRunning,
            candidateCount: candidateCount,
            verifiedCount: verifiedCount,
            publishedFindingCount: publishedFindingCount,
            hiddenFindingCount: hiddenFindingCount,
            gates: [
                ReviewPipelineGateState(title: "Verification", isReady: verificationGateReady),
                ReviewPipelineGateState(title: "Patch", isReady: patchGateReady),
            ],
            tools: toolExecutions.map {
                ReviewPipelineToolExecution(
                    id: $0.id,
                    title: ReviewPipelineJobStateBuilder.displayTitle(for: $0.id),
                    status: $0.status.reviewToolStatus,
                    findingsCount: $0.findingsCount
                )
            },
            bundleModes: bundleModes,
            isTerminal: isTerminal
        )
    }
}

private struct ReviewPanelRustToolExecution: Decodable {
    let id: String
    let status: String
    let findingsCount: Int
}

private extension String {
    var reviewToolStatus: ReviewPipelineToolExecution.Status {
        switch self {
        case "completed":
            return .completed
        case "running":
            return .running
        default:
            return .pending
        }
    }

    var reviewPanelWarmState: ReviewPanelWarmState {
        switch self {
        case "warming":
            return .warming
        case "failed":
            return .failed
        case "idle":
            return .idle
        default:
            return .ready
        }
    }
}

private extension Dictionary where Key == String, Value == Int {
    var findingSeverityCounts: [FindingSeverity: Int] {
        reduce(into: [FindingSeverity: Int]()) { partialResult, entry in
            if let severity = FindingSeverity(rawValue: entry.key) {
                partialResult[severity] = entry.value
            }
        }
    }
}
