import XCTest
@testable import CoderIDE

final class MainChatRawCallbackOwnershipPolicyTests: XCTestCase {
    func testTurnStartedDoesNotSplitStreamingAssistantWhenPipelineArtifactsAreOwnedElsewhere() {
        XCTAssertFalse(
            shouldSplitStreamingAssistantOnRawTurnStarted(
                shouldApplyPipelineArtifacts: false,
                shouldUseLinearChat: true
            )
        )
    }

    func testTurnStartedCanSplitWhenLinearChatOwnsPipelineArtifacts() {
        XCTAssertTrue(
            shouldSplitStreamingAssistantOnRawTurnStarted(
                shouldApplyPipelineArtifacts: true,
                shouldUseLinearChat: true
            )
        )
    }

    func testAssistantUpdateDoesNotProjectIntoLiveChatWhenPipelineArtifactsAreOwnedElsewhere() {
        XCTAssertFalse(
            shouldProjectRawAssistantUpdateIntoLiveChat(
                shouldApplyPipelineArtifacts: false,
                providerId: "codex-cli"
            )
        )
    }

    func testAssistantUpdateProjectsIntoLiveChatOnlyForCodexWhenLocalPipelineArtifactsAreEnabled() {
        XCTAssertTrue(
            shouldProjectRawAssistantUpdateIntoLiveChat(
                shouldApplyPipelineArtifacts: true,
                providerId: "codex-cli"
            )
        )
        XCTAssertFalse(
            shouldProjectRawAssistantUpdateIntoLiveChat(
                shouldApplyPipelineArtifacts: true,
                providerId: "claude-cli"
            )
        )
    }
}
