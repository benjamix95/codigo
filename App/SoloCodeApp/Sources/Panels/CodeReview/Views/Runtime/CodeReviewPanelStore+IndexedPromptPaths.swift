import Foundation

extension CodeReviewPanelStore {
    private static let codebaseAuditIncludedPathsCapPro = 12_000

    private func promptCap(for depth: ReviewScanDepth) -> Int {
        switch depth {
        case .fast: 96
        case .standard: 480
        case .pro: 8_000
        }
    }

    private func auditIncludedCap(for depth: ReviewScanDepth) -> Int {
        switch depth {
        case .fast: 600
        case .standard: 6_000
        case .pro: Self.codebaseAuditIncludedPathsCapPro
        }
    }

    /// Una transizione actor + cap per profondità (evita migliaia di await sull’indice prima del run).
    func gatherCodebaseIndexedPathsForRun(depth: ReviewScanDepth) async -> (
        promptPaths: [String],
        workspaceIncludedPaths: [String]
    ) {
        let index = workspaceStore.codebaseIndex
        let pCap = promptCap(for: depth)
        let auditCap = max(pCap, auditIncludedCap(for: depth))
        return await index.gatherSourcePathsForPanelReview(
            promptCap: pCap,
            auditCap: auditCap
        )
    }

    /// Percorsi relativi dall’indice da allegare al prompt (solo scope codebase; cap in base a `ReviewScanDepth`).
    func gatherCodebasePromptFilePaths(scope: ReviewScopeTarget, depth: ReviewScanDepth) async -> [String] {
        guard case .codebase = scope else { return [] }
        let split = await gatherCodebaseIndexedPathsForRun(depth: depth)
        return split.promptPaths
    }
}
