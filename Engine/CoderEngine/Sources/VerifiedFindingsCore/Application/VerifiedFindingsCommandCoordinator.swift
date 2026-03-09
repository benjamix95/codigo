import Foundation

public enum VerifiedFindingsCommandOutcome: Sendable, Equatable {
    case executed(summary: String)
    case deduplicated(summary: String)
}

public actor VerifiedFindingsCommandCoordinator {
    public static let shared = VerifiedFindingsCommandCoordinator()

    private let deduplicationService = CommandDeduplicationService()
    private let executionCoordinator = EntityExecutionCoordinator()

    public init() {}

    public func execute(
        meta: VerifiedCommandMeta,
        successSummary: String,
        operation: @Sendable () async throws -> Void
    ) async throws -> VerifiedFindingsCommandOutcome {
        if let existing = await deduplicationService.existingRecord(for: meta) {
            return .deduplicated(summary: existing.resultSummary)
        }

        try await executionCoordinator.withExclusiveAccess(entityId: meta.entityId) {
            try await operation()
        }
        _ = await deduplicationService.record(meta: meta, resultSummary: successSummary)
        return .executed(summary: successSummary)
    }
}
