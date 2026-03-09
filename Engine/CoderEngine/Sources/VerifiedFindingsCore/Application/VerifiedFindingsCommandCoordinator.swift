import Foundation

public enum VerifiedFindingsCommandError: Error, Equatable {
    case versionUnavailable(entityId: String)
    case versionConflict(expected: Int, actual: Int)
}

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
        currentEntityVersion: (@Sendable () async throws -> Int?)? = nil,
        operation: @Sendable () async throws -> Void
    ) async throws -> VerifiedFindingsCommandOutcome {
        if let existing = await deduplicationService.existingRecord(for: meta) {
            return .deduplicated(summary: existing.resultSummary)
        }

        try await executionCoordinator.withExclusiveAccess(entityId: meta.entityId) {
            if let expectedVersion = meta.expectedEntityVersion {
                guard let currentEntityVersion else {
                    throw VerifiedFindingsCommandError.versionUnavailable(entityId: meta.entityId)
                }
                guard let actualVersion = try await currentEntityVersion() else {
                    throw VerifiedFindingsCommandError.versionUnavailable(entityId: meta.entityId)
                }
                guard actualVersion == expectedVersion else {
                    throw VerifiedFindingsCommandError.versionConflict(
                        expected: expectedVersion,
                        actual: actualVersion
                    )
                }
            }
            try await operation()
        }
        _ = await deduplicationService.record(meta: meta, resultSummary: successSummary)
        return .executed(summary: successSummary)
    }
}
