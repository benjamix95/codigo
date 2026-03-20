import XCTest
import CoderEngine
@testable import CoderIDE

final class RustMainChatProviderFactoryTests: XCTestCase {
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
}
