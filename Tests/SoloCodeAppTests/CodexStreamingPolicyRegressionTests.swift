import XCTest
@testable import CoderIDE

final class CodexStreamingPolicyRegressionTests: XCTestCase {
    func testCodexProviderAliasesNeverRouteTextToReasoningInAgentMode() {
        let providerIds = [
            "codex-cli",
            "codex",
            "codex-preview",
            "my-codex-backend",
        ]

        for providerId in providerIds {
            XCTAssertFalse(
                shouldRouteStreamingTextToReasoning(
                    coderMode: .agent,
                    hasOperationalActivityInTurn: false,
                    providerId: providerId
                ),
                "Codex provider \(providerId) should stream into the answer bubble, not reasoning."
            )
        }
    }

    func testCodexProviderAliasesStayOutOfReasoningEvenAfterOperationalActivity() {
        let providerIds = ["codex-cli", "codex", "codex-enterprise"]

        for providerId in providerIds {
            XCTAssertFalse(
                shouldRouteStreamingTextToReasoning(
                    coderMode: .agent,
                    hasOperationalActivityInTurn: true,
                    providerId: providerId
                )
            )
        }
    }

    func testNonCodexProvidersStillUseReasoningRouteInAgentMode() {
        let providerIds = ["gemini-cli", "openai-api", ""]

        for providerId in providerIds {
            XCTAssertTrue(
                shouldRouteStreamingTextToReasoning(
                    coderMode: .agent,
                    hasOperationalActivityInTurn: false,
                    providerId: providerId
                ),
                "Non-Codex provider \(providerId) should keep the legacy reasoning route."
            )
        }
    }

    func testIDEModeNeverRoutesStreamingTextToReasoning() {
        let providerIds = ["codex-cli", "codex", "claude-cli", "gemini-cli", ""]

        for providerId in providerIds {
            XCTAssertFalse(
                shouldRouteStreamingTextToReasoning(
                    coderMode: .ide,
                    hasOperationalActivityInTurn: false,
                    providerId: providerId
                )
            )
        }
    }

    func testCodexUsesStandardStreamWhenRustTransportIsAvailable() {
        XCTAssertEqual(
            resolveMainChatSendExecutionRoute(
                coderMode: .agent,
                isPlanMultiTurnFlow: false,
                usesRustTransport: true
            ),
            .standardStream
        )
        XCTAssertEqual(
            resolveMainChatSendExecutionRoute(
                coderMode: .agent,
                isPlanMultiTurnFlow: true,
                usesRustTransport: true
            ),
            .standardStream
        )
    }

    func testCodexFallsBackToAgentPipelineWhenRustTransportIsUnavailable() {
        XCTAssertEqual(
            resolveMainChatSendExecutionRoute(
                coderMode: .agent,
                isPlanMultiTurnFlow: false,
                usesRustTransport: false
            ),
            .agentPipeline
        )
    }

    func testCodexAssistantUpdatesProjectIntoLiveChatOnlyWhenPipelineArtifactsAreOwnedLocally() {
        XCTAssertTrue(
            shouldProjectRawAssistantUpdateIntoLiveChat(
                shouldApplyPipelineArtifacts: true,
                providerId: "codex-cli"
            )
        )
        XCTAssertFalse(
            shouldProjectRawAssistantUpdateIntoLiveChat(
                shouldApplyPipelineArtifacts: false,
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

    func testRawTurnStartedSplitRequiresLinearOwnership() {
        XCTAssertTrue(
            shouldSplitStreamingAssistantOnRawTurnStarted(
                shouldApplyPipelineArtifacts: true,
                shouldUseLinearChat: true
            )
        )
        XCTAssertFalse(
            shouldSplitStreamingAssistantOnRawTurnStarted(
                shouldApplyPipelineArtifacts: true,
                shouldUseLinearChat: false
            )
        )
        XCTAssertFalse(
            shouldSplitStreamingAssistantOnRawTurnStarted(
                shouldApplyPipelineArtifacts: false,
                shouldUseLinearChat: true
            )
        )
    }
}
