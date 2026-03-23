import XCTest
import CoderEngine
@testable import CoderIDE

final class RustMainChatProviderFactoryTests: XCTestCase {
    override func setUp() {
        super.setUp()
        setenv("SOLOCODE_REVIEW_CORE_LIBRARY_PATH", reviewCoreLibraryPath(from: #filePath), 1)
        unsetenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT")
        unsetenv("SOLOCODE_REVIEW_CORE_DISABLE_RUST")
        ReviewCoreBridge.resetForTests()
    }

    override func tearDown() {
        unsetenv("SOLOCODE_REVIEW_CORE_LIBRARY_PATH")
        unsetenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT")
        unsetenv("SOLOCODE_REVIEW_CORE_DISABLE_RUST")
        ReviewCoreBridge.resetForTests()
        super.tearDown()
    }

    func testTransportProviderReflectsInjectedAuthenticationState() {
        let provider = MainChatRustTransportProvider(
            id: "codex-cli",
            displayName: "Codex",
            attachmentCapabilities: .none,
            authenticated: true,
            config: baseConfig()
        )

        XCTAssertEqual(provider.id, "codex-cli")
        XCTAssertTrue(provider.isAuthenticated())
    }

    func testAttachmentBridgeMapsTypedAttachment() {
        let url = URL(fileURLWithPath: "/tmp/image.png")
        let attachment = MainChatProviderAttachmentBridge(
            LLMAttachment(kind: .image, url: url, mimeType: "image/png", filename: "image.png", sizeBytes: 42)
        )

        XCTAssertEqual(attachment.kind, "image")
        XCTAssertEqual(attachment.filePath, "/tmp/image.png")
        XCTAssertEqual(attachment.filename, "image.png")
    }

    func testStreamEventMappingPreservesRawPayload() {
        let event = MainChatProviderEventBridge(
            kind: .raw,
            text: "",
            rawType: "usage",
            payload: ["input_tokens": "12", "output_tokens": "34"]
        )

        guard case .raw(let type, let payload)? = MainChatProviderBridgeSupport.streamEvent(from: event) else {
            return XCTFail("Expected raw stream event")
        }
        XCTAssertEqual(type, "usage")
        XCTAssertEqual(payload["input_tokens"], "12")
    }

    func testCLIAccountSnapshotsCanAuthenticateRustTransportWithoutLegacyAdapter() {
        let cliAccounts = [
            MainChatCLIAccountSnapshotBridge(
                id: UUID().uuidString,
                provider: "codex",
                label: "Primary",
                isEnabled: true,
                isAuthenticated: true,
                priority: 0,
                profilePath: "/tmp/codex",
                envOverrides: [:],
                quota: MainChatCLIQuotaSnapshotBridge(.empty),
                health: MainChatCLIHealthSnapshotBridge(.healthy),
                createdAt: nil,
                updatedAt: nil
            )
        ]

        XCTAssertTrue(
            MainChatRustTransportSupport.isAuthenticated(
                baseAuthenticated: false,
                cliAccounts: cliAccounts
            )
        )
    }

    func testProviderFactoryConfigResolvesDetectedCodexPathForRustTransport() {
        let config = makeProviderFactoryConfig(codexPath: "")

        XCTAssertEqual(
            config.resolvedCodexPath { customPath in
                XCTAssertNil(customPath)
                return "/tmp/detected-codex"
            },
            "/tmp/detected-codex"
        )
    }

    func testProviderFactoryConfigPreservesConfiguredCodexPathForRustTransportResolution() {
        let config = makeProviderFactoryConfig(codexPath: "/tmp/custom-codex")

        XCTAssertEqual(
            config.resolvedCodexPath { customPath in
                XCTAssertEqual(customPath, "/tmp/custom-codex")
                return customPath
            },
            "/tmp/custom-codex"
        )
    }

    func testRuntimeTransportResolutionUsesRustBoundaryForReadOnlyPlan() {
        let config = makeProviderFactoryConfig(codexPath: "")

        let resolved = MainChatRustTransportSupport.resolveTransportConfig(
            selectedProviderId: "codex-cli",
            fallbackSelectedProviderId: "codex-cli",
            coderMode: .plan,
            shouldRunPlanInline: false,
            forcePlanInline: false,
            preferCodeReviewRuntimeProvider: nil,
            config: config
        )

        XCTAssertEqual(resolved?.providerId, "codex-cli")
        XCTAssertEqual(resolved?.backend, .codexCli)
        XCTAssertEqual(resolved?.codexSandbox, "workspace-read")
        XCTAssertFalse(resolved?.codexSessionFullAccess ?? true)
        XCTAssertEqual(resolved?.claudeAllowedTools, ["Read", "Glob", "Grep"])
    }

    func testRustTransportBypassDoesNotTriggerForCodexWhenRuntimeEnabled() {
        var config = makeProviderFactoryConfig(codexPath: "")
        config.unifiedToolRuntimeEnabled = true

        XCTAssertFalse(
            MainChatRustTransportSupport.shouldBypassRustTransport(
                selectedProviderId: "codex-cli",
                fallbackSelectedProviderId: nil,
                config: config
            )
        )
    }

    func testRustTransportBypassDoesNotTriggerWhenUnifiedRuntimeDisabled() {
        var config = makeProviderFactoryConfig(codexPath: "")
        config.unifiedToolRuntimeEnabled = false

        XCTAssertFalse(
            MainChatRustTransportSupport.shouldBypassRustTransport(
                selectedProviderId: "codex-cli",
                fallbackSelectedProviderId: nil,
                config: config
            )
        )
    }

    func testRuntimeTransportResolutionFailsClosedWhenRustBridgeIsDisabled() {
        setenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT", "1", 1)
        ReviewCoreBridge.resetForTests()
        defer {
            unsetenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT")
            ReviewCoreBridge.resetForTests()
        }

        let resolved = MainChatRustTransportSupport.resolveTransportConfig(
            selectedProviderId: "codex-cli",
            fallbackSelectedProviderId: "codex-cli",
            coderMode: .agent,
            shouldRunPlanInline: false,
            forcePlanInline: false,
            preferCodeReviewRuntimeProvider: nil,
            config: makeProviderFactoryConfig(codexPath: "")
        )

        XCTAssertNil(resolved)
    }

    func testAgentSendExecutionRouteFallsBackToPipelineWhenProviderDoesNotUseRustTransport() {
        XCTAssertEqual(
            resolveMainChatSendExecutionRoute(
                coderMode: .agent,
                isPlanMultiTurnFlow: false,
                usesRustTransport: false
            ),
            .agentPipeline
        )
    }

    func testAgentSendExecutionRouteUsesStandardStreamWhenRustTransportIsAvailable() {
        XCTAssertEqual(
            resolveMainChatSendExecutionRoute(
                coderMode: .agent,
                isPlanMultiTurnFlow: false,
                usesRustTransport: true
            ),
            .standardStream
        )
    }

    func testPlanSendExecutionRouteKeepsPlanFlowPriorityOverProviderTransport() {
        XCTAssertEqual(
            resolveMainChatSendExecutionRoute(
                coderMode: .agent,
                isPlanMultiTurnFlow: true,
                usesRustTransport: false
            ),
            .planFlow
        )
    }

    private func baseConfig() -> MainChatProviderSessionConfigBridge {
        MainChatProviderSessionConfigBridge(
            providerId: "codex-cli",
            displayName: "Codex",
            backend: .codexCli,
            workspacePath: "/tmp",
            workspacePaths: ["/tmp"],
            prompt: "",
            systemPrompt: nil,
            contextPrompt: nil,
            model: nil,
            apiKey: nil,
            baseURL: nil,
            toolDefinitionsJson: nil,
            extraHeaders: [:],
            codexPath: "/usr/bin/codex",
            codexSandbox: "workspace-write",
            codexAskForApproval: "never",
            codexModelOverride: nil,
            codexReasoningEffort: nil,
            codexModelProvider: nil,
            codexFastMode: true,
            codexSessionFullAccess: false,
            codexPreferResponsesWireAPI: false,
            claudePath: nil,
            claudeModel: nil,
            claudeAllowedTools: [],
            geminiCliPath: nil,
            geminiModelOverride: nil,
            attachments: [],
            cliAccounts: []
        )
    }

    private func makeProviderFactoryConfig(codexPath: String) -> ProviderFactoryConfig {
        ProviderFactoryConfig(
            openaiApiKey: "",
            openaiModel: "",
            anthropicApiKey: "",
            anthropicModel: "",
            googleApiKey: "",
            googleModel: "",
            minimaxApiKey: "",
            minimaxModel: "",
            openrouterApiKey: "",
            openrouterModel: "",
            grokApiKey: "",
            grokModel: "",
            codexPath: codexPath,
            codexSandbox: "workspace-write",
            codexSessionFullAccess: false,
            codexAskForApproval: "never",
            codexModelOverride: "",
            codexReasoningEffort: "",
            codexFastMode: false,
            codexModelProvider: "",
            codexPreferResponsesWireAPI: false,
            planModeBackend: "codex",
            swarmOrchestrator: "auto",
            swarmWorkerBackend: "auto",
            swarmEnabledRoles: "",
            globalYolo: false,
            codeReviewPartitions: 1,
            codeReviewAnalysisOnly: false,
            codeReviewMaxRounds: 1,
            codeReviewAnalysisBackend: "codex-cli",
            codeReviewExecutionBackend: "codex-cli",
            claudePath: "",
            claudeModel: "",
            claudeAllowedTools: [],
            geminiCliPath: "",
            geminiModelOverride: "",
            unifiedToolRuntimeEnabled: false,
            agentsHardBlockEnabled: false,
            mcpEditEnforcementEnabled: false,
            webSearchProvider: "",
            braveSearchApiKey: "",
            tavilyApiKey: "",
            serperApiKey: ""
        )
    }

}
