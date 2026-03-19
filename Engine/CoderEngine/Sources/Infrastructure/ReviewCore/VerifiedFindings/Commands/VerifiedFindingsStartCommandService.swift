import Foundation

public enum VerifiedFindingsStartCommandError: Error, Equatable {
    case invalidScope(String)
    case missingRef
    case invalidRef(String)
    case invalidMaxWorkers
    case invalidMaxRounds
    case invalidAnalysisOnly
    case invalidBackend(field: String, value: String)
    case invalidSessionId(String)
    case sessionAlreadyExists(String)
    case sessionAlreadyQueued(String)
}

public struct VerifiedFindingsStartCommandRequest: Sendable, Equatable {
    public let scope: String
    public let ref: String?
    public let sessionId: String
    public let conversationId: UUID?
    public let payload: [String: String]

    public init(
        scope: String,
        ref: String? = nil,
        sessionId: String,
        conversationId: UUID?,
        payload: [String: String]
    ) {
        self.scope = scope
        self.ref = ref
        self.sessionId = sessionId
        self.conversationId = conversationId
        self.payload = payload
    }
}

public enum VerifiedFindingsStartCommandService {
    private static let validScopes: Set<String> = ["uncommitted", "staged", "against_ref"]
    private static let validBackends: Set<String> = [
        "auto", "codex", "claude", "gemini",
        "codex-cli", "claude-cli", "gemini-cli",
        "openrouter", "openrouter-api",
        "minimax", "minimax-api",
        "grok", "grok-api",
        "openai", "openai-api",
        "anthropic", "anthropic-api",
        "google", "google-api",
    ]

    public static func makeRequest(
        args: [String: String],
        conversationId: UUID?
    ) throws -> VerifiedFindingsStartCommandRequest {
        let requestedScope = (args["scope"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let scope = requestedScope.isEmpty ? "uncommitted" : requestedScope
        guard validScopes.contains(scope) else {
            throw VerifiedFindingsStartCommandError.invalidScope(requestedScope)
        }

        let ref = (args["ref"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if scope == "against_ref" {
            guard !ref.isEmpty else {
                throw VerifiedFindingsStartCommandError.missingRef
            }
            guard CodeReviewMultiSwarmProvider.isValidAgainstRefFormat(ref) else {
                throw VerifiedFindingsStartCommandError.invalidRef(ref)
            }
        }

        if let maxWorkers = args["max_workers"],
           !maxWorkers.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let value = Int(maxWorkers.trimmingCharacters(in: .whitespacesAndNewlines)),
                  (1 ... 12).contains(value) else {
                throw VerifiedFindingsStartCommandError.invalidMaxWorkers
            }
        }

        if let maxRounds = args["max_rounds"],
           !maxRounds.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let value = Int(maxRounds.trimmingCharacters(in: .whitespacesAndNewlines)),
                  (1 ... 10).contains(value) else {
                throw VerifiedFindingsStartCommandError.invalidMaxRounds
            }
        }

        if let analysisOnly = args["analysis_only"],
           !analysisOnly.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let normalized = analysisOnly.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let validValues = ["1", "0", "true", "false", "yes", "no", "y", "n"]
            guard validValues.contains(normalized) else {
                throw VerifiedFindingsStartCommandError.invalidAnalysisOnly
            }
        }

        for field in ["analysis_backend", "execution_backend"] {
            if let backend = args[field],
               !backend.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               !validBackends.contains(backend.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) {
                throw VerifiedFindingsStartCommandError.invalidBackend(
                    field: field,
                    value: backend
                )
            }
        }

        let requestedSessionId = (args["session_id"] ?? args["sessionId"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let sessionId: String
        if requestedSessionId.isEmpty {
            sessionId = UUID().uuidString.lowercased()
        } else if let sanitized = MCPSharedState.sanitizedCodeReviewSessionId(requestedSessionId) {
            sessionId = sanitized
        } else {
            throw VerifiedFindingsStartCommandError.invalidSessionId(requestedSessionId)
        }

        var payload = args.filter { !$0.key.isEmpty }
        payload["scope"] = scope
        payload["session_id"] = sessionId
        if payload["conversation_id"] == nil,
           let conversationId {
            payload["conversation_id"] = conversationId.uuidString.lowercased()
        }
        return VerifiedFindingsStartCommandRequest(
            scope: scope,
            ref: ref.isEmpty ? nil : ref,
            sessionId: sessionId,
            conversationId: conversationId,
            payload: payload
        )
    }

    public static func enqueueReviewStart(
        request: VerifiedFindingsStartCommandRequest
    ) throws -> MCPSharedCodeReviewCommand {
        if MCPSharedState.readCodeReviewSnapshot(sessionId: request.sessionId) != nil {
            throw VerifiedFindingsStartCommandError.sessionAlreadyExists(request.sessionId)
        }
        do {
            return try MCPSharedState.enqueueUniqueCodeReviewStartCommand(
                sessionId: request.sessionId,
                conversationId: request.conversationId,
                payload: request.payload
            )
        } catch MCPSharedState.CodeReviewStartEnqueueError.sessionAlreadyQueued {
            throw VerifiedFindingsStartCommandError.sessionAlreadyQueued(request.sessionId)
        }
    }
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

public extension BugHunterWorkflowService {
    static func makeStartRequest(
        runId: String,
        reviewSessionId: String,
        sourceKind: MCPSharedBugHunterSourceKind,
        againstRef: String?,
        prompt: String,
        maxRounds: Int,
        maxWorkers: Int,
        conversationId: UUID? = nil
    ) throws -> VerifiedFindingsStartCommandRequest {
        try VerifiedFindingsStartCommandService.makeRequest(
            args: [
                "scope": againstRef == nil ? "uncommitted" : "against_ref",
                "ref": againstRef ?? "",
                "session_id": reviewSessionId,
                "analysis_only": "true",
                "max_rounds": String(maxRounds),
                "max_workers": String(maxWorkers),
                "bughunter_run_id": runId,
                "bughunter_profile": sourceKind == .commit ? "commit_review" : "deep",
                "bughunter_prompt_override": prompt,
                "auto_prepare_verified_patches": "true",
                "auto_prepare_origin_filter": FindingOrigin.bugHunter.rawValue,
            ],
            conversationId: conversationId
        )
    }
}
