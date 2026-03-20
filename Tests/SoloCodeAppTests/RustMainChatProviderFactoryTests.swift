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

    @MainActor
    func testProjectUIDecodesSelectedConversationFromRustBoundary() throws {
        guard ReviewCoreBridge.isEnabled else {
            throw XCTSkip("Bridge Rust non disponibile nei test app-side")
        }
        let state = makeUIState()
        let snapshot = try XCTUnwrap(RustMainChatStoreAdapter.projectUI(state))
        XCTAssertEqual(snapshot.selectedConversationId, state.selectedConversationId)
        XCTAssertEqual(snapshot.messages.first?.primaryText, "Hello from Rust")
        XCTAssertTrue(snapshot.task.isLoading)
    }

    @MainActor
    func testHandleUIIntentTogglesCollapsedArtifactState() throws {
        guard ReviewCoreBridge.isEnabled else {
            throw XCTSkip("Bridge Rust non disponibile nei test app-side")
        }
        let response = try XCTUnwrap(
            RustMainChatStoreAdapter.handleUIIntent(
                MainChatUIIntentRequestBridge(
                    schemaVersion: 1,
                    intent: "toggle_artifact_collapsed",
                    state: makeUIState(),
                    conversationId: nil,
                    turnId: "turn-1",
                    artifactId: "artifact-1",
                    text: nil,
                    timestamp: nil,
                    payload: [:]
                )
            )
        )
        XCTAssertEqual(response.state?.collapsedArtifactIdsByTurn["turn-1"], ["artifact-1"])
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

    private func makeUIState() -> MainChatUIStateBridge {
        MainChatUIStateBridge(
            storeSnapshot: MainChatStoreSnapshotBridge(
                conversations: [
                    MainChatStoreConversationSnapshotBridge(
                        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!.uuidString.lowercased(),
                        threadRootConversationId: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!.uuidString.lowercased(),
                        title: "Main",
                        messages: [
                            MainChatStoreMessageSnapshotBridge(
                                id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!.uuidString.lowercased(),
                                role: "assistant",
                                content: "Hello",
                                primaryTextSnapshot: "Hello",
                                blocks: nil,
                                turnMetadata: nil,
                                isStreaming: true,
                                imagePaths: nil,
                                attachments: nil,
                                planAttachment: nil,
                                reasoningText: nil,
                                subagentCards: nil
                            )
                        ],
                        createdAt: nil,
                        contextId: nil,
                        contextFolderPath: nil,
                        mode: "Agent",
                        preferredProviderId: "codex-cli",
                        contextMemorySummaryMarkdown: nil,
                        contextMemoryGeneratedAt: nil,
                        contextMemorySourceMessageCount: nil,
                        isArchived: false,
                        isPinned: false,
                        isFavorite: false,
                        lastInputTokens: nil,
                        workspaceId: nil,
                        adHocFolderPaths: [],
                        checkpoints: []
                    )
                ],
                planBoards: [:]
            ),
            runtimeSnapshot: MainChatRuntimeSnapshotBridge(
                turnState: MainChatBridgeState(
                    conversationId: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
                    assistantMessageId: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
                    turnId: "turn-1",
                    providerId: "codex-cli",
                    sequence: 1,
                    isStreaming: true,
                    startedAt: Date(timeIntervalSinceReferenceDate: 10),
                    completedAt: nil,
                    updatedAt: Date(timeIntervalSinceReferenceDate: 10),
                    status: "streaming",
                    orderedTextStreamIds: ["main"],
                    textByStreamId: ["main": "Hello from Rust"],
                    reasoningByGroupId: [:],
                    artifacts: [
                        ChatArtifact(
                            id: "artifact-1",
                            kind: .status,
                            title: "Status",
                            text: "Running",
                            items: [],
                            metadata: [:],
                            isCollapsible: true,
                            isCollapsedByDefault: false
                        )
                    ]
                ),
                mode: .directStream,
                directStream: nil,
                plan: nil,
                output: MainChatRuntimeOutputBridge(
                    chatContentOverride: nil,
                    shouldHidePlanMarkdown: false,
                    shouldOpenPlanPanel: false,
                    shouldFinalizeStream: false,
                    shouldRetryPoll: false,
                    followUpPrompt: nil,
                    generatedPrompt: nil,
                    terminalError: nil
                )
            ),
            taskRuntimeState: MainChatTaskRuntimeStateBridge(
                taskStates: [
                    MainChatTaskStateSnapshotBridge(
                        conversationId: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!.uuidString.lowercased(),
                        startedAt: Date(timeIntervalSinceReferenceDate: 10),
                        statusText: "Running"
                    )
                ]
            ),
            selectedConversationId: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!.uuidString.lowercased(),
            draftText: "continue",
            planPanelVisible: false,
            followLive: true,
            collapsedArtifactIdsByTurn: [:]
        )
    }
}
