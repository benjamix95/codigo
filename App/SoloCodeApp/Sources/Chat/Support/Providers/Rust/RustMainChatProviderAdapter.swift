import Foundation
import CoderEngine

final class MainChatRustTransportProvider: LLMProvider, @unchecked Sendable {
    let id: String
    let displayName: String
    let attachmentCapabilities: ProviderAttachmentCapabilities

    private let baseConfig: MainChatProviderSessionConfigBridge
    private let authenticated: Bool

    init(
        id: String,
        displayName: String,
        attachmentCapabilities: ProviderAttachmentCapabilities,
        authenticated: Bool,
        config: MainChatProviderSessionConfigBridge
    ) {
        self.id = id
        self.displayName = displayName
        self.attachmentCapabilities = attachmentCapabilities
        self.authenticated = authenticated
        self.baseConfig = config
    }

    func isAuthenticated() -> Bool {
        authenticated
    }

    func send(
        prompt: String,
        context: WorkspaceContext,
        imageURLs: [URL]?
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let attachments = imageURLs?.map {
            LLMAttachment(kind: .image, url: $0, filename: $0.lastPathComponent)
        }
        return try await send(prompt: prompt, context: context, attachments: attachments)
    }

    func send(
        prompt: String,
        context: WorkspaceContext,
        attachments: [LLMAttachment]?
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        let sessionId = UUID().uuidString.lowercased()
        let config = resolvedConfig(prompt: prompt, context: context, attachments: attachments)
        return AsyncThrowingStream { continuation in
            let driver = Task {
                let start: MainChatProviderSessionResponseBridge? = ReviewCoreBridge.call(
                    functionName: "chat_core_provider_start_session",
                    request: MainChatProviderSessionStartRequestBridge(
                        schemaVersion: 1,
                        sessionId: sessionId,
                        config: config
                    )
                )
                if let message = start?.error?.message {
                    continuation.yield(.error(message))
                    continuation.finish(throwing: CoderEngineError.apiError(message))
                    return
                }

                var finished = false
                while !finished && !Task.isCancelled {
                    let response: MainChatProviderSessionResponseBridge? = ReviewCoreBridge.call(
                        functionName: "chat_core_provider_resume",
                        request: MainChatProviderSessionRequestBridge(schemaVersion: 1, sessionId: sessionId)
                    )
                    if let message = response?.error?.message {
                        continuation.yield(.error(message))
                        continuation.finish(throwing: CoderEngineError.apiError(message))
                        return
                    }

                    for event in response?.events ?? [] {
                        switch event.kind {
                        case .started:
                            continuation.yield(.started)
                        case .textDelta:
                            continuation.yield(.textDelta(event.text))
                        case .textReplace:
                            continuation.yield(.textReplace(event.text))
                        case .raw:
                            continuation.yield(.raw(type: event.rawType ?? "provider_raw", payload: event.payload))
                        case .error:
                            let message = event.text.isEmpty ? "Provider stream failed" : event.text
                            continuation.yield(.error(message))
                            continuation.finish(throwing: CoderEngineError.apiError(message))
                            return
                        case .completed:
                            continuation.yield(.completed)
                            continuation.finish()
                            return
                        }
                    }

                    if let snapshot = response?.snapshot {
                        if snapshot.status == "completed" || snapshot.status == "cancelled" {
                            continuation.yield(.completed)
                            continuation.finish()
                            finished = true
                            break
                        }
                        if snapshot.status == "failed" {
                            let message = snapshot.terminalError ?? "Provider session failed"
                            continuation.yield(.error(message))
                            continuation.finish(throwing: CoderEngineError.apiError(message))
                            return
                        }
                    }

                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
            }

            continuation.onTermination = { _ in
                driver.cancel()
                let _: MainChatProviderSessionResponseBridge? = ReviewCoreBridge.call(
                    functionName: "chat_core_provider_cancel",
                    request: MainChatProviderSessionRequestBridge(schemaVersion: 1, sessionId: sessionId)
                )
            }
        }
    }

    private func resolvedConfig(
        prompt: String,
        context: WorkspaceContext,
        attachments: [LLMAttachment]?
    ) -> MainChatProviderSessionConfigBridge {
        let systemPrompt = context.systemPromptOverride ?? SystemPrompts.taskCompletionStrict
        let contextPrompt = context.contextPrompt()
        return MainChatProviderSessionConfigBridge(
            providerId: baseConfig.providerId,
            displayName: baseConfig.displayName,
            backend: baseConfig.backend,
            workspacePath: context.workspacePath.path,
            workspacePaths: context.workspacePaths.map(\.path),
            prompt: prompt,
            systemPrompt: systemPrompt,
            contextPrompt: contextPrompt.isEmpty ? nil : contextPrompt,
            model: baseConfig.model,
            apiKey: baseConfig.apiKey,
            baseURL: baseConfig.baseURL,
            toolDefinitionsJson: baseConfig.toolDefinitionsJson,
            extraHeaders: baseConfig.extraHeaders,
            codexPath: baseConfig.codexPath,
            codexSandbox: baseConfig.codexSandbox,
            codexAskForApproval: baseConfig.codexAskForApproval,
            codexModelOverride: baseConfig.codexModelOverride,
            codexReasoningEffort: baseConfig.codexReasoningEffort,
            codexModelProvider: baseConfig.codexModelProvider,
            codexFastMode: baseConfig.codexFastMode,
            codexSessionFullAccess: baseConfig.codexSessionFullAccess,
            codexPreferResponsesWireAPI: baseConfig.codexPreferResponsesWireAPI,
            claudePath: baseConfig.claudePath,
            claudeModel: baseConfig.claudeModel,
            claudeAllowedTools: baseConfig.claudeAllowedTools,
            geminiCliPath: baseConfig.geminiCliPath,
            geminiModelOverride: baseConfig.geminiModelOverride,
            attachments: (attachments ?? []).map(MainChatProviderAttachmentBridge.init),
            cliAccounts: baseConfig.cliAccounts
        )
    }
}
