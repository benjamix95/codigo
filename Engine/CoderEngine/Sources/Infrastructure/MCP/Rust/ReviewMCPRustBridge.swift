import Foundation

public struct ReviewMCPToolBridgeResult: Sendable, Equatable {
    public let message: String
    public let isError: Bool
}

public enum ReviewMCPRustBridge {
    public static func handleReviewTool(
        toolName: String,
        args: [String: String],
        reviewSnapshots: [CodeReviewSessionSnapshot],
        activeReviewSnapshot: CodeReviewSessionSnapshot?,
        reviewFindingsPayload: [[String: String]] = [],
        reviewStatusPayload: [String: String]? = nil,
        reviewOutcomePayload: [String: String]? = nil
    ) -> ReviewMCPToolBridgeResult? {
        call(
            functionName: "review_core_mcp_handle_tool",
            request: RustMCPToolRequest(
                schemaVersion: 1,
                toolName: toolName,
                args: args,
                reviewSnapshots: reviewSnapshots.map(RustMCPSnapshotRecord.init(snapshot:)),
                activeReviewSnapshot: activeReviewSnapshot.map(RustMCPSnapshotRecord.init(snapshot:)),
                reviewFindingsPayload: reviewFindingsPayload,
                reviewStatusPayload: reviewStatusPayload,
                reviewOutcomePayload: reviewOutcomePayload,
                bughunterSnapshots: [],
                activeBughunterSnapshot: nil,
                bughunterFindingsPayload: [],
                bughunterClusterPayload: nil,
                securityGatePayload: nil
            )
        )
    }

    public static func handleSecurityTool(
        toolName: String,
        args: [String: String],
        reviewSnapshots: [CodeReviewSessionSnapshot],
        activeReviewSnapshot: CodeReviewSessionSnapshot?,
        securityFindingsPayload: [[String: String]],
        reviewStatusPayload: [String: String]?,
        securityGatePayload: [String: String]?
    ) -> ReviewMCPToolBridgeResult? {
        call(
            functionName: "review_core_security_handle_tool",
            request: RustMCPToolRequest(
                schemaVersion: 1,
                toolName: toolName,
                args: args,
                reviewSnapshots: reviewSnapshots.map(RustMCPSnapshotRecord.init(snapshot:)),
                activeReviewSnapshot: activeReviewSnapshot.map(RustMCPSnapshotRecord.init(snapshot:)),
                reviewFindingsPayload: securityFindingsPayload,
                reviewStatusPayload: reviewStatusPayload,
                reviewOutcomePayload: nil,
                bughunterSnapshots: [],
                activeBughunterSnapshot: nil,
                bughunterFindingsPayload: [],
                bughunterClusterPayload: nil,
                securityGatePayload: securityGatePayload
            )
        )
    }

    public static func handleBugHunterTool(
        toolName: String,
        args: [String: String],
        bughunterSnapshots: [MCPSharedBugHunterSnapshot],
        activeBughunterSnapshot: MCPSharedBugHunterSnapshot?,
        bughunterFindingsPayload: [[String: String]] = [],
        bughunterClusterPayload: [String: String]? = nil
    ) -> ReviewMCPToolBridgeResult? {
        call(
            functionName: "review_core_bughunter_handle_tool",
            request: RustMCPToolRequest(
                schemaVersion: 1,
                toolName: toolName,
                args: args,
                reviewSnapshots: [],
                activeReviewSnapshot: nil,
                reviewFindingsPayload: [],
                reviewStatusPayload: nil,
                reviewOutcomePayload: nil,
                bughunterSnapshots: bughunterSnapshots.map(RustMCPBugHunterSnapshotRecord.init(snapshot:)),
                activeBughunterSnapshot: activeBughunterSnapshot.map(RustMCPBugHunterSnapshotRecord.init(snapshot:)),
                bughunterFindingsPayload: bughunterFindingsPayload,
                bughunterClusterPayload: bughunterClusterPayload,
                securityGatePayload: nil
            )
        )
    }

    private static func call<Request: Encodable>(
        functionName: String,
        request: Request
    ) -> ReviewMCPToolBridgeResult? {
        guard let response: RustMCPToolResponse = ReviewCoreBridge.call(
            functionName: functionName,
            request: request
        ) else {
            return nil
        }
        return ReviewMCPToolBridgeResult(
            message: response.message,
            isError: response.isError
        )
    }
}

private struct RustMCPToolRequest: Encodable {
    let schemaVersion: Int
    let toolName: String
    let args: [String: String]
    let reviewSnapshots: [RustMCPSnapshotRecord]
    let activeReviewSnapshot: RustMCPSnapshotRecord?
    let reviewFindingsPayload: [[String: String]]
    let reviewStatusPayload: [String: String]?
    let reviewOutcomePayload: [String: String]?
    let bughunterSnapshots: [RustMCPBugHunterSnapshotRecord]
    let activeBughunterSnapshot: RustMCPBugHunterSnapshotRecord?
    let bughunterFindingsPayload: [[String: String]]
    let bughunterClusterPayload: [String: String]?
    let securityGatePayload: [String: String]?
}

private struct RustMCPToolResponse: Decodable {
    let message: String
    let isError: Bool
}

private struct RustMCPBugHunterSnapshotRecord: Encodable {
    let runId: String
    let conversationId: String?
    let reviewSessionId: String?
    let sourceKind: String
    let triggerKind: String
    let gitRoot: String
    let branchName: String?
    let primaryCommit: String?
    let relatedCommits: [String]
    let status: String
    let lastMessage: String?
    let verifiedFindingsCount: Int
    let candidateFindingsCount: Int
    let lastRevalidationVerdict: String?
    let securityGateReady: Bool?

    init(snapshot: MCPSharedBugHunterSnapshot) {
        self.runId = snapshot.runId
        self.conversationId = snapshot.conversationId
        self.reviewSessionId = snapshot.reviewSessionId
        self.sourceKind = snapshot.sourceKind.rawValue
        self.triggerKind = snapshot.triggerKind.rawValue
        self.gitRoot = snapshot.gitRoot
        self.branchName = snapshot.branchName
        self.primaryCommit = snapshot.primaryCommit
        self.relatedCommits = snapshot.relatedCommits
        self.status = snapshot.status.rawValue
        self.lastMessage = snapshot.lastMessage
        self.verifiedFindingsCount = snapshot.verifiedFindingsCount
        self.candidateFindingsCount = snapshot.candidateFindingsCount
        self.lastRevalidationVerdict = snapshot.lastRevalidationVerdict
        self.securityGateReady = snapshot.securityGateReady
    }
}
