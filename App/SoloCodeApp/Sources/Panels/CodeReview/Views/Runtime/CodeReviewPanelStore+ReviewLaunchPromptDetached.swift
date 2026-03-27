import CoderEngine
import Foundation

private enum ReviewLaunchDetachedPathCaps {
    static let codebaseAuditIncludedPathsCapPro = 12_000
}

extension CodeReviewPanelStore {

    /// Solo raccolta indice (scope codebase). Eseguito off-MainActor quando serve `promptOverride` senza rifare `combinedPrompt`.
    nonisolated static func gatherCodebasePathsForLaunchIfNeeded(
        scope: ReviewScopeTarget,
        scanDepth: ReviewScanDepth,
        codebaseIndex: CodebaseIndex
    ) async -> (promptPaths: [String], workspaceIncludedPaths: [String]?) {
        guard case .codebase = scope else {
            return ([], nil)
        }
        let pCap: Int
        switch scanDepth {
        case .fast: pCap = 96
        case .standard: pCap = 480
        case .pro: pCap = 8_000
        }
        let auditOnly: Int
        switch scanDepth {
        case .fast: auditOnly = 600
        case .standard: auditOnly = 6_000
        case .pro: auditOnly = ReviewLaunchDetachedPathCaps.codebaseAuditIncludedPathsCapPro
        }
        let auditCap = max(pCap, auditOnly)
        let split = await codebaseIndex.gatherSourcePathsForPanelReview(
            promptCap: pCap,
            auditCap: auditCap
        )
        let included = split.workspaceIncludedPaths.isEmpty ? nil : split.workspaceIncludedPaths
        return (split.promptPaths, included)
    }

    /// FFI `buildPanelPrompt` + eventuale gather indice: **non** sul MainActor così la UI resta reattiva durante la preparazione.
    nonisolated static func buildReviewLaunchPromptOffMainActor(
        scope: ReviewScopeTarget,
        modes: Set<CodeReviewPanelMode>,
        scanDepth: ReviewScanDepth,
        currentBranch: String,
        customInstructions: String,
        codebaseIndex: CodebaseIndex
    ) async -> (prompt: String, workspaceIncludedPaths: [String]?) {
        #if DEBUG
        let splitT0 = Date()
        #endif
        let (paths, included) = await gatherCodebasePathsForLaunchIfNeeded(
            scope: scope,
            scanDepth: scanDepth,
            codebaseIndex: codebaseIndex
        )
        #if DEBUG
        let splitT1 = Date()
        #endif
        var modesForBridge = modes
        modesForBridge.insert(.standard)
        let prompt = ReviewPanelCoordinator.combinedPrompt(
            scope: scope,
            currentBranch: currentBranch,
            selectedModes: modesForBridge,
            customInstructions: customInstructions,
            scanDepth: scanDepth,
            codebaseFilePaths: paths
        )
        #if DEBUG
        let splitT2 = Date()
        ReviewPanelDebugNDJSON.emit(
            hypothesisId: "H_prompt_build",
            location: "CodeReviewPanelStore+ReviewLaunchPromptDetached.buildReviewLaunchPromptOffMainActor",
            message: "off_main_prompt_build_split",
            data: [
                "gatherMs": Int(splitT1.timeIntervalSince(splitT0) * 1000),
                "combinedMs": Int(splitT2.timeIntervalSince(splitT1) * 1000),
                "promptPathCount": paths.count,
                "scopeKind": String(describing: scope),
                "depth": scanDepth.rawValue,
                "workspaceIncludedCount": included?.count ?? 0,
            ]
        )
        #endif
        return (prompt, included)
    }
}
