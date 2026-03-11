import Foundation

public struct ReviewPatchRustBridge {
    public static func queueContext(
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

    public static func executionPlan(
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
                status: $0.status.rawValue,
                verifyStatus: $0.verifyStatus.rawValue,
                validationStatus: $0.validationStatus.rawValue,
                riskScore: $0.riskScore
            )
        }
        self.findings = snapshot.findings.map {
            ReviewPatchRustFinding(
                id: $0.id,
                status: $0.status.rawValue,
                severity: $0.severity.rawValue,
                category: $0.category.rawValue,
                message: $0.message,
                patchArtifactId: $0.patchArtifactId
            )
        }
    }
}

private struct ReviewPatchRustPatch: Encodable {
    let id: String
    let findingId: String
    let status: String
    let verifyStatus: String
    let validationStatus: String
    let riskScore: Double
}

private struct ReviewPatchRustFinding: Encodable {
    let id: String
    let status: String
    let severity: String
    let category: String
    let message: String
    let patchArtifactId: String?
}

public struct ReviewPatchRustResponse: Decodable {
    public let isError: Bool
    public let errorCode: String?
    public let errorMessage: String?
    public let steps: [String]
    public let patchId: String?
    public let patchVerifyStatus: String?
    public let patchRiskScore: Double?
    public let findingSeverity: String?
    public let findingCategory: String?
    public let findingMessage: String?
}
