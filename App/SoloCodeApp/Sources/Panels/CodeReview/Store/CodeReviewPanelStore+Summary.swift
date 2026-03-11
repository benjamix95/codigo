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

    var currentLiveCandidates: [ReviewCandidate] {
        currentReviewPanelDerivedState?.liveCandidates ?? []
    }

    var currentVerifiedFindings: [CodeReviewFinding] {
        currentReviewPanelDerivedState?.verifiedFindings ?? []
    }

    var currentPublishedFindings: [CodeReviewFinding] {
        currentReviewPanelDerivedState?.publishReadyFindings ?? []
    }

    var currentVisibleFindings: [CodeReviewFinding] {
        currentVerifiedFindings + currentPublishedFindings
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
        let publishedFindingIDs = rustPanelState?.publishReadyFindingIds
            ?? publishReadyFindingIDsFallback(snapshot: effectiveSnapshot)
        let verifiedFindingIDs = rustPanelState?.verifiedFindingIds
            ?? verifiedFindingIDsFallback(snapshot: effectiveSnapshot)
        let liveCandidateIDs = rustPanelState?.liveCandidateIds
            ?? effectiveSnapshot.candidates.map(\.id)
        let findingsById = Dictionary(uniqueKeysWithValues: effectiveSnapshot.findings.map { ($0.id, $0) })
        let candidatesById = Dictionary(uniqueKeysWithValues: effectiveSnapshot.candidates.map { ($0.id, $0) })
        let liveCandidates = liveCandidateIDs.compactMap { candidatesById[$0] }
        let verifiedFindings = verifiedFindingIDs.compactMap { findingsById[$0] }
        let publishReadyFindings = publishedFindingIDs.compactMap { findingsById[$0] }
        let pipelineJobState = rustPanelState?.makePipelineJobState()
            ?? ReviewPipelineJobStateBuilder.build(
                snapshot: effectiveSnapshot,
                entryPoint: .panel
            )
        let publishedSeverityCounts = rustPanelState?.publishedSeverityCounts.findingSeverityCounts
            ?? Dictionary(grouping: publishReadyFindings, by: \.severity).reduce(into: [FindingSeverity: Int]()) { partialResult, entry in
                partialResult[entry.key] = entry.value.count
            }
        let emptyStateTitle = rustPanelState?.emptyStateTitle
            ?? fallbackEmptyStateTitle(snapshot: effectiveSnapshot, pipeline: pipelineJobState)
        let emptyStateSubtitle = rustPanelState?.emptyStateSubtitle
            ?? fallbackEmptyStateSubtitle(snapshot: effectiveSnapshot, pipeline: pipelineJobState)

        let derivedState = ReviewPanelDerivedState(
            sessionId: effectiveSnapshot.sessionId,
            mutationSequence: effectiveSnapshot.mutationSequence,
            liveCandidates: liveCandidates,
            verifiedFindings: verifiedFindings,
            publishReadyFindings: publishReadyFindings,
            publishedSeverityCounts: publishedSeverityCounts,
            pipelineJobState: pipelineJobState,
            projection: verifiedEnvelope.projectionSnapshot,
            verifiedEnvelope: verifiedEnvelope,
            phaseLedger: rustPanelState?.phaseLedger ?? effectiveSnapshot.phaseLedger,
            fileLedger: rustPanelState?.fileLedger ?? effectiveSnapshot.fileLedger,
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

    private static func publishReadyFindingIDsFallback(
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

    private static func verifiedFindingIDsFallback(
        snapshot: CodeReviewSessionSnapshot
    ) -> [String] {
        guard let envelope = snapshot.verifiedFindings else { return [] }
        let publishReady = Set(publishReadyFindingIDsFallback(snapshot: snapshot))
        let verifiedIds = Set(envelope.projectionSnapshot.verifiedQueue.map(\.id))
        return snapshot.findings.compactMap { finding in
            guard verifiedIds.contains(finding.id), !publishReady.contains(finding.id) else { return nil }
            let isVerified = finding.verifiedAt != nil || finding.verificationReport != nil
            return isVerified ? finding.id : nil
        }
    }

    private static func fallbackEmptyStateTitle(
        snapshot: CodeReviewSessionSnapshot,
        pipeline: ReviewPipelineJobState?
    ) -> String {
        pipeline == nil ? "No findings yet" : "Waiting for review evidence"
    }

    private static func fallbackEmptyStateSubtitle(
        snapshot: CodeReviewSessionSnapshot,
        pipeline: ReviewPipelineJobState?
    ) -> String {
        if let pipeline {
            if pipeline.candidateCount > 0 {
                return "I candidati live sono visibili mentre la verifica è ancora in corso."
            }
            if pipeline.verifiedCount > pipeline.publishedFindingCount {
                return "I finding verificati sono visibili anche se la patch finale è ancora in preparazione."
            }
            if pipeline.hiddenFindingCount > 0 {
                return "Verification and patch preparation are still gating the findings."
            }
            if pipeline.isTerminal {
                return "The run completed without any verified or publish-ready findings."
            }
            return "The pipeline is still running. Live candidates and verified findings appear progressively."
        }
        return "Start a review to analyze your code"
    }
}
