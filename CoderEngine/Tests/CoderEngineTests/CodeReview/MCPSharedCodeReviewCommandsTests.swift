import XCTest
@testable import CoderEngine

final class MCPSharedCodeReviewCommandsTests: XCTestCase {
    override func setUp() {
        super.setUp()
        try? FileManager.default.removeItem(at: MCPSharedState.codeReviewDirectoryPath)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: MCPSharedState.codeReviewDirectoryPath)
        super.tearDown()
    }


    func testEnqueueCommandDropsInvalidSessionId() {
        let command = MCPSharedState.enqueueCodeReviewCommand(
            action: "start",
            sessionId: "../escape",
            conversationId: nil,
            payload: ["scope": "uncommitted"]
        )

        XCTAssertNil(command.sessionId)
    }

    func testEnqueueCommandDropsSessionIdStartingWithPunctuation() {
        let command = MCPSharedState.enqueueCodeReviewCommand(
            action: "start",
            sessionId: "_session",
            conversationId: nil,
            payload: ["scope": "uncommitted"]
        )

        XCTAssertNil(command.sessionId)
    }

    func testClaimPendingCommandsPromotesThemToProcessing() throws {
        _ = MCPSharedState.enqueueCodeReviewCommand(
            action: "start",
            sessionId: "session-1",
            conversationId: nil,
            payload: ["scope": "uncommitted"]
        )
        _ = MCPSharedState.enqueueCodeReviewCommand(
            action: "configure",
            sessionId: "session-1",
            conversationId: nil,
            payload: ["max_workers": "4"]
        )

        let claimed = MCPSharedState.claimPendingCodeReviewCommands()

        XCTAssertEqual(claimed.count, 2)
        XCTAssertTrue(claimed.allSatisfy { $0.status == .processing })
        XCTAssertTrue(MCPSharedState.readPendingCodeReviewCommands().isEmpty)
    }

    func testEnqueueUniqueStartRejectsDuplicatePendingSessionId() throws {
        _ = try MCPSharedState.enqueueUniqueCodeReviewStartCommand(
            sessionId: "session-1",
            conversationId: nil,
            payload: ["scope": "uncommitted"]
        )

        XCTAssertThrowsError(
            try MCPSharedState.enqueueUniqueCodeReviewStartCommand(
                sessionId: "session-1",
                conversationId: nil,
                payload: ["scope": "staged"]
            )
        ) { error in
            XCTAssertEqual(
                error as? MCPSharedState.CodeReviewStartEnqueueError,
                .sessionAlreadyQueued
            )
        }
    }

    func testClaimPendingCommandsReclaimsStaleProcessingCommands() throws {
        try FileManager.default.createDirectory(
            at: MCPSharedState.codeReviewDirectoryPath,
            withIntermediateDirectories: true
        )

        let stale = MCPSharedCodeReviewCommand(
            id: "cmd-1",
            action: "comment",
            sessionId: "session-1",
            conversationId: nil,
            payload: ["finding_id": "f1"],
            createdAt: Date(timeIntervalSinceNow: -600),
            updatedAt: Date(timeIntervalSinceNow: -600),
            status: .processing,
            resultMessage: nil
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode([stale])
        try data.write(to: MCPSharedState.codeReviewCommandsFilePath, options: .atomic)

        let claimed = MCPSharedState.claimPendingCodeReviewCommands()

        XCTAssertEqual(claimed.map(\.id), ["cmd-1"])
        XCTAssertEqual(claimed.first?.status, .processing)
    }

    func testHeartbeatRefreshPreventsStaleProcessingCommandFromBeingReclaimed() throws {
        try FileManager.default.createDirectory(
            at: MCPSharedState.codeReviewDirectoryPath,
            withIntermediateDirectories: true
        )

        let stale = MCPSharedCodeReviewCommand(
            id: "cmd-heartbeat",
            action: "start",
            sessionId: "session-1",
            conversationId: nil,
            payload: ["scope": "uncommitted"],
            createdAt: Date(timeIntervalSinceNow: -600),
            updatedAt: Date(timeIntervalSinceNow: -600),
            status: .processing,
            resultMessage: nil
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode([stale])
        try data.write(to: MCPSharedState.codeReviewCommandsFilePath, options: .atomic)

        MCPSharedState.refreshCodeReviewCommandHeartbeat(id: "cmd-heartbeat")
        let claimed = MCPSharedState.claimPendingCodeReviewCommands()

        XCTAssertTrue(claimed.isEmpty)
    }
}
