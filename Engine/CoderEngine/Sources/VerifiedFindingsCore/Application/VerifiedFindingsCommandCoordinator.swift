import Foundation

public struct VerifiedCommandDeduplicationRecord: Sendable, Codable, Equatable {
    public let commandId: String
    public let requestFingerprint: String
    public let entityId: String
    public let resultSummary: String
    public let recordedAt: Date
}

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

public extension BugHunterWorkflowService {
    static func queueLifecycleCommand(
        action: String,
        sessionId: String,
        findingId: String,
        conversationId: UUID?,
        payload: [String: String]
    ) throws -> VerifiedFindingsQueuedCommandContext {
        try VerifiedFindingsLifecycleCommandService.queueCommand(
            action: action,
            sessionId: sessionId,
            findingId: findingId,
            conversationId: conversationId,
            payload: payload
        )
    }
}

public actor EntityExecutionCoordinator {
    private var activeEntities: Set<String> = []

    public init() {}

    public func withExclusiveAccess<T: Sendable>(
        entityId: String,
        operation: @Sendable () async throws -> T
    ) async rethrows -> T {
        while activeEntities.contains(entityId) {
            await Task.yield()
        }
        activeEntities.insert(entityId)
        defer { activeEntities.remove(entityId) }
        return try await operation()
    }
}

public actor CommandDeduplicationService {
    private var recordsByCommandId: [String: VerifiedCommandDeduplicationRecord] = [:]
    private var recordsByFingerprint: [String: VerifiedCommandDeduplicationRecord] = [:]

    public init() {}

    public func existingRecord(for meta: VerifiedCommandMeta) -> VerifiedCommandDeduplicationRecord? {
        if let byCommand = recordsByCommandId[meta.commandId] {
            return byCommand
        }
        return recordsByFingerprint[fingerprintKey(meta)]
    }

    public func record(
        meta: VerifiedCommandMeta,
        resultSummary: String,
        recordedAt: Date = Date()
    ) -> VerifiedCommandDeduplicationRecord {
        let record = VerifiedCommandDeduplicationRecord(
            commandId: meta.commandId,
            requestFingerprint: meta.requestFingerprint,
            entityId: meta.entityId,
            resultSummary: resultSummary,
            recordedAt: recordedAt
        )
        recordsByCommandId[meta.commandId] = record
        recordsByFingerprint[fingerprintKey(meta)] = record
        return record
    }

    private func fingerprintKey(_ meta: VerifiedCommandMeta) -> String {
        "\(meta.entityId)|\(meta.requestFingerprint)"
    }
}
