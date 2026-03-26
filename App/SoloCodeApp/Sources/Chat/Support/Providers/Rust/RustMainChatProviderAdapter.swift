import Foundation
import CoderEngine

final class MainChatRustTransportProvider: LLMProvider, @unchecked Sendable {
    typealias StartSessionBridge = (MainChatProviderSessionStartRequestBridge) -> MainChatProviderSessionResponseBridge?
    typealias PollSessionBridge = (MainChatProviderSessionPollRequestBridge) -> MainChatProviderSessionResponseBridge?
    typealias CancelSessionBridge = (MainChatProviderSessionRequestBridge) -> MainChatProviderSessionResponseBridge?
    typealias RuntimePollBridge = (MainChatRuntimeProviderPollBridgeRequest) -> MainChatRuntimeProviderPollBridgeResponse?

    let id: String
    let displayName: String
    let attachmentCapabilities: ProviderAttachmentCapabilities

    private let baseConfig: MainChatProviderSessionConfigBridge
    private let authenticated: Bool
    private let startSessionBridge: StartSessionBridge
    private let pollSessionBridge: PollSessionBridge
    private let cancelSessionBridge: CancelSessionBridge
    private let runtimePollBridge: RuntimePollBridge

    init(
        id: String,
        displayName: String,
        attachmentCapabilities: ProviderAttachmentCapabilities,
        authenticated: Bool,
        config: MainChatProviderSessionConfigBridge,
        startSessionBridge: @escaping StartSessionBridge = {
            ReviewCoreBridge.call(functionName: "chat_core_provider_start_session", request: $0)
        },
        pollSessionBridge: @escaping PollSessionBridge = {
            ReviewCoreBridge.call(functionName: "chat_core_provider_poll", request: $0)
        },
        cancelSessionBridge: @escaping CancelSessionBridge = {
            ReviewCoreBridge.call(functionName: "chat_core_provider_cancel", request: $0)
        },
        runtimePollBridge: @escaping RuntimePollBridge = {
            ReviewCoreBridge.call(functionName: "chat_core_runtime_poll_provider", request: $0)
        }
    ) {
        self.id = id
        self.displayName = displayName
        self.attachmentCapabilities = attachmentCapabilities
        self.authenticated = authenticated
        self.baseConfig = config
        self.startSessionBridge = startSessionBridge
        self.pollSessionBridge = pollSessionBridge
        self.cancelSessionBridge = cancelSessionBridge
        self.runtimePollBridge = runtimePollBridge
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
        let config = runtimeSessionConfig(prompt: prompt, context: context, attachments: attachments)
        return AsyncThrowingStream { continuation in
            let driver = Task {
                let start = startSessionBridge(
                    MainChatProviderSessionStartRequestBridge(
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
                    let response = pollSessionBridge(
                        MainChatProviderSessionPollRequestBridge(
                            schemaVersion: 1,
                            sessionId: sessionId,
                            timeoutMs: 50
                        )
                    )
                    if let message = response?.error?.message {
                        continuation.yield(.error(message))
                        continuation.finish(throwing: CoderEngineError.apiError(message))
                        return
                    }

                    let events = response?.events ?? []
                    for event in events {
                        switch event.kind {
                        case .started:
                            print("[BRIDGE_DEBUG] event=started")
                            continuation.yield(.started)
                        case .textDelta:
                            print("[BRIDGE_DEBUG] event=textDelta len=\(event.text.count) preview=\(String(event.text.prefix(80)))")
                            continuation.yield(.textDelta(event.text))
                        case .textReplace:
                            print("[BRIDGE_DEBUG] event=textReplace len=\(event.text.count)")
                            continuation.yield(.textReplace(event.text))
                        case .raw:
                            let rt = event.rawType ?? "provider_raw"
                            print("[BRIDGE_DEBUG] event=raw type=\(rt) keys=\(event.payload.keys.sorted())")
                            continuation.yield(.raw(type: rt, payload: event.payload))
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
                }
            }

            continuation.onTermination = { _ in
                // Notify Rust FIRST so the worker thread sees the cancelled
                // flag and can exit its blocking read loop before the Swift
                // Task cancellation propagates and the pipe is closed.
                let _ = self.cancelSessionBridge(
                    MainChatProviderSessionRequestBridge(schemaVersion: 1, sessionId: sessionId)
                )
                driver.cancel()
            }
        }
    }

    func startRuntimeSession(
        prompt: String,
        context: WorkspaceContext,
        attachments: [LLMAttachment]?
    ) throws -> String {
        let sessionId = UUID().uuidString.lowercased()
        let config = runtimeSessionConfig(prompt: prompt, context: context, attachments: attachments)
        let start = startSessionBridge(
            MainChatProviderSessionStartRequestBridge(
                schemaVersion: 1,
                sessionId: sessionId,
                config: config
            )
        )
        if let message = start?.error?.message {
            throw CoderEngineError.apiError(message)
        }
        return sessionId
    }

    func cancelRuntimeSession(sessionId: String) {
        let _ = cancelSessionBridge(
            MainChatProviderSessionRequestBridge(schemaVersion: 1, sessionId: sessionId)
        )
    }

    func pollRuntime(
        sessionId: String,
        providerId: String,
        snapshot: MainChatRuntimeSnapshotBridge,
        timeoutMs: Int
    ) -> MainChatRuntimeProviderPollBridgeResponse? {
        runtimePollBridge(
            MainChatRuntimeProviderPollBridgeRequest(
                schemaVersion: 1,
                sessionId: sessionId,
                providerId: providerId,
                snapshot: snapshot,
                timeoutMs: timeoutMs
            )
        )
    }

    func runtimeSessionConfig(
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
            claudeMcpServerPath: baseConfig.claudeMcpServerPath,
            geminiCliPath: baseConfig.geminiCliPath,
            geminiModelOverride: baseConfig.geminiModelOverride,
            kiloPath: baseConfig.kiloPath,
            kiloModel: baseConfig.kiloModel,
            attachments: (attachments ?? []).map(MainChatProviderAttachmentBridge.init),
            cliAccounts: baseConfig.cliAccounts
        )
    }
}
