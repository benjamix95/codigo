import XCTest
@testable import CoderEngine

final class VerifiedFindingsStartCommandServiceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        try? FileManager.default.removeItem(at: MCPSharedState.codeReviewDirectoryPath)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: MCPSharedState.codeReviewDirectoryPath)
        super.tearDown()
    }

    func testMakeRequestRejectsInvalidScope() {
        XCTAssertThrowsError(
            try VerifiedFindingsStartCommandService.makeRequest(
                args: ["scope": "invalid"],
                conversationId: nil
            )
        ) { error in
            XCTAssertEqual(
                error as? VerifiedFindingsStartCommandError,
                .invalidScope("invalid")
            )
        }
    }

    func testMakeRequestRequiresRefForAgainstRef() {
        XCTAssertThrowsError(
            try VerifiedFindingsStartCommandService.makeRequest(
                args: ["scope": "against_ref"],
                conversationId: nil
            )
        ) { error in
            XCTAssertEqual(
                error as? VerifiedFindingsStartCommandError,
                .missingRef
            )
        }
    }

    func testEnqueueReviewStartRejectsDuplicateQueuedSession() throws {
        let request = try VerifiedFindingsStartCommandService.makeRequest(
            args: ["session_id": "session-1"],
            conversationId: nil
        )
        _ = try VerifiedFindingsStartCommandService.enqueueReviewStart(request: request)

        XCTAssertThrowsError(
            try VerifiedFindingsStartCommandService.enqueueReviewStart(request: request)
        ) { error in
            XCTAssertEqual(
                error as? VerifiedFindingsStartCommandError,
                .sessionAlreadyQueued("session-1")
            )
        }
    }

    func testMakeRequestNormalizesPayloadAndConversation() throws {
        let conversationId = UUID()
        let request = try VerifiedFindingsStartCommandService.makeRequest(
            args: [
                "scope": "staged",
                "session_id": "session-2",
                "analysis_only": "true",
            ],
            conversationId: conversationId
        )

        XCTAssertEqual(request.scope, "staged")
        XCTAssertEqual(request.sessionId, "session-2")
        XCTAssertEqual(request.payload["scope"], "staged")
        XCTAssertEqual(request.payload["session_id"], "session-2")
        XCTAssertEqual(
            request.payload["conversation_id"],
            conversationId.uuidString.lowercased()
        )
    }
}
