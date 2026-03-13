import CoderEngine
import Foundation

@MainActor
enum ReviewPatchRuntimeFinalizationService {
    typealias PrepareHandler = @MainActor (
        CodeReviewSessionSnapshot,
        [String],
        String,
        any LLMProvider
    ) async throws -> CodeReviewSessionSnapshot

    static var prepareHandler: PrepareHandler = defaultPrepareVerifiedPatches

    static func prepareVerifiedPatches(
        snapshot: CodeReviewSessionSnapshot,
        findingIds: [String],
        workspaceRoot: String,
        executionProvider: any LLMProvider
    ) async throws -> CodeReviewSessionSnapshot {
        try await prepareHandler(
            snapshot,
            findingIds,
            workspaceRoot,
            executionProvider
        )
    }

    static func resetForTests() {
        prepareHandler = defaultPrepareVerifiedPatches
    }

    private static func defaultPrepareVerifiedPatches(
        snapshot: CodeReviewSessionSnapshot,
        findingIds: [String],
        workspaceRoot: String,
        executionProvider: any LLMProvider
    ) async throws -> CodeReviewSessionSnapshot {
        let service = ReviewPatchWorkflowService()
        var current = snapshot

        for findingId in findingIds {
            guard let finding = current.findings.first(where: { $0.id == findingId }) else {
                continue
            }
            do {
                let prepared = try await service.preparePatch(
                    finding: finding,
                    snapshot: current,
                    executionProvider: executionProvider,
                    workspaceRoot: workspaceRoot
                )
                let verified = try await service.verifyPatch(
                    artifact: prepared,
                    workspaceRoot: workspaceRoot
                )
                current = VerifiedFindingsService.upsertingPatch(
                    in: current,
                    artifact: verified
                )
            } catch {
                let findings = current.findings.map { item -> CodeReviewFinding in
                    guard item.id == findingId else { return item }
                    var updated = item
                    updated.status = .patchFailed
                    updated.comments.append(
                        FindingComment(
                            author: "system",
                            content: "Patch preview non disponibile: \(error.localizedDescription)"
                        )
                    )
                    return updated
                }
                current = current.copying(
                    findings: findings,
                    outcome: current.copying(findings: findings).buildOutcomeSummary(
                        summaryOverride: "Patch preparation failed for \(findingId): \(error.localizedDescription)"
                    )
                )
            }
        }

        return current
    }
}
