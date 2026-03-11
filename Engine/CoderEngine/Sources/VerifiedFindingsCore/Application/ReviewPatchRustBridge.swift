import Foundation

struct ReviewPatchRustBridge {
    static func queueContext(
        action: String,
        sessionId: String,
        findingId: String,
        conversationId: UUID?,
        snapshot: CodeReviewSessionSnapshot
    ) -> ReviewPatchRustResponse? {
        call(
            operation: "queue_context",
            action: action,
            sessionId: sessionId,
            findingId: findingId,
            conversationId: conversationId,
            snapshot: snapshot
        )
    }

    static func executionPlan(
        action: String,
        sessionId: String,
        findingId: String,
        conversationId: UUID?,
        snapshot: CodeReviewSessionSnapshot
    ) -> ReviewPatchRustResponse? {
        call(
            operation: "plan_execution",
            action: action,
            sessionId: sessionId,
            findingId: findingId,
            conversationId: conversationId,
            snapshot: snapshot
        )
    }

    private static func call(
        operation: String,
        action: String,
        sessionId: String,
        findingId: String,
        conversationId: UUID?,
        snapshot: CodeReviewSessionSnapshot
    ) -> ReviewPatchRustResponse? {
        ReviewCoreBridge.call(
            functionName: "review_core_patch_handle_action",
            request: ReviewPatchRustRequest(
                schemaVersion: 1,
                operation: operation,
                action: action,
                sessionId: sessionId,
                findingId: findingId,
                conversationId: conversationId?.uuidString.lowercased(),
                snapshot: ReviewPatchRustSnapshot(snapshot: snapshot)
            )
        )
    }
}

private struct ReviewPatchRustRequest: Encodable {
    let schemaVersion: Int
    let operation: String
    let action: String
    let sessionId: String
    let findingId: String
    let conversationId: String?
    let snapshot: ReviewPatchRustSnapshot
}

private struct ReviewPatchRustSnapshot: Encodable {
    let sessionId: String
    let conversationId: String?
    let findingIds: [String]
    let candidateIds: [String]
    let patches: [ReviewPatchRustPatch]
    let findings: [ReviewPatchRustFinding]

    init(snapshot: CodeReviewSessionSnapshot) {
        self.sessionId = snapshot.sessionId
        self.conversationId = snapshot.conversationId?.uuidString.lowercased()
        self.findingIds = snapshot.findings.map(\.id)
        self.candidateIds = snapshot.candidates.map(\.id)
        self.patches = snapshot.patches.map {
            ReviewPatchRustPatch(
                id: $0.id,
                findingId: $0.findingId,
                verifyStatus: $0.verifyStatus.rawValue,
                riskScore: $0.riskScore
            )
        }
        self.findings = snapshot.findings.map {
            ReviewPatchRustFinding(
                id: $0.id,
                severity: $0.severity.rawValue,
                category: $0.category.rawValue,
                message: $0.message
            )
        }
    }
}

private struct ReviewPatchRustPatch: Encodable {
    let id: String
    let findingId: String
    let verifyStatus: String
    let riskScore: Double
}

private struct ReviewPatchRustFinding: Encodable {
    let id: String
    let severity: String
    let category: String
    let message: String
}

struct ReviewPatchRustResponse: Decodable {
    let isError: Bool
    let errorCode: String?
    let errorMessage: String?
    let steps: [String]
    let patchId: String?
    let patchVerifyStatus: String?
    let patchRiskScore: Double?
    let findingSeverity: String?
    let findingCategory: String?
    let findingMessage: String?
}
