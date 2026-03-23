import CoderEngine
import Foundation

private struct MainChatReasoningBlockBridge: Codable, Equatable {
    let id: String
    let text: String
}

private struct MainChatReasoningSegmentBridge: Codable, Equatable {
    let id: String
    let kind: String
    let text: String
}

private struct MainChatReasoningStateBridge: Codable, Equatable {
    let blocks: [MainChatReasoningBlockBridge]
    let text: String?
    let segments: [MainChatReasoningSegmentBridge]
}

private struct MainChatReasoningRequestBridge: Encodable {
    let schemaVersion: Int
    let operation: String
    let providerId: String?
    let separateCodexThinkingMessagesEnabled: Bool?
    let eventConversationId: String?
    let selectedConversationId: String?
    let output: String?
    let groupId: String?
    let state: MainChatReasoningStateBridge?
    let sequentialStreamingLayoutEnabled: Bool?
    let streamingSegmentTurnIndex: Int?
}

private struct MainChatReasoningResponseBridge: Decodable {
    let schemaVersion: Int
    let error: MainChatBridgeError?
    let presentationMode: String?
    let isCodexProvider: Bool?
    let shouldUpdateInlineReasoningState: Bool?
    let state: MainChatReasoningStateBridge?
}

enum ChatReasoningPresentationMode: String {
    case inline
    case separateMessages
}

private func shouldAllowSwiftReasoningFallback(environment: [String: String]) -> Bool {
    shouldDeferRustReviewCoreBootstrap(environment: environment)
}

func shouldUpdateInlineReasoningState(
    eventConversationId: UUID?,
    selectedConversationId: UUID?
) -> Bool {
    let response: MainChatReasoningResponseBridge? = ReviewCoreBridge.call(
        functionName: "chat_core_reasoning_handle",
        request: MainChatReasoningRequestBridge(
            schemaVersion: 1,
            operation: "should_update_inline_reasoning_state",
            providerId: nil,
            separateCodexThinkingMessagesEnabled: nil,
            eventConversationId: eventConversationId?.uuidString.lowercased(),
            selectedConversationId: selectedConversationId?.uuidString.lowercased(),
            output: nil,
            groupId: nil,
            state: nil,
            sequentialStreamingLayoutEnabled: nil,
            streamingSegmentTurnIndex: nil
        )
    )
    if let result = response?.shouldUpdateInlineReasoningState {
        return result
    }
    guard shouldAllowSwiftReasoningFallback(environment: ProcessInfo.processInfo.environment) else {
        return false
    }
    guard let eventId = eventConversationId, let selectedId = selectedConversationId else {
        return false
    }
    return eventId == selectedId
}

enum ChatReasoningPresentationPolicy {
    static func isCodexProvider(_ providerId: String) -> Bool {
        let response: MainChatReasoningResponseBridge? = ReviewCoreBridge.call(
            functionName: "chat_core_reasoning_handle",
            request: MainChatReasoningRequestBridge(
                schemaVersion: 1,
                operation: "is_codex_provider",
                providerId: providerId,
                separateCodexThinkingMessagesEnabled: nil,
                eventConversationId: nil,
                selectedConversationId: nil,
                output: nil,
                groupId: nil,
                state: nil,
                sequentialStreamingLayoutEnabled: nil,
                streamingSegmentTurnIndex: nil
            )
        )
        return response?.isCodexProvider ?? false
    }

    static func mode(
        providerId: String,
        separateCodexThinkingMessagesEnabled: Bool
    ) -> ChatReasoningPresentationMode {
        _ = providerId
        _ = separateCodexThinkingMessagesEnabled
        // Main chat reasoning must remain provider-agnostic so Codex uses the
        // same inline presentation grammar as the other providers.
        return .inline
    }
}

struct ChatReasoningStreamReducer {
    struct State {
        var blocks: [ReasoningBlock]
        var text: String?
        var segments: [MessageSegment]
    }

    static func apply(
        output: String,
        groupId: String,
        state: State,
        sequentialStreamingLayoutEnabled: Bool,
        streamingSegmentTurnIndex: Int
    ) -> State {
        let response: MainChatReasoningResponseBridge? = ReviewCoreBridge.call(
            functionName: "chat_core_reasoning_handle",
            request: MainChatReasoningRequestBridge(
                schemaVersion: 1,
                operation: "apply_stream_chunk",
                providerId: nil,
                separateCodexThinkingMessagesEnabled: nil,
                eventConversationId: nil,
                selectedConversationId: nil,
                output: output,
                groupId: groupId,
                state: MainChatReasoningStateBridge(
                    blocks: state.blocks.map { .init(id: $0.id, text: $0.text) },
                    text: state.text,
                    segments: state.segments.map {
                        switch $0.kind {
                        case .reasoning(let text):
                            return .init(id: $0.id, kind: "reasoning", text: text)
                        case .text(let text):
                            return .init(id: $0.id, kind: "text", text: text)
                        case .toolTrace:
                            return .init(id: $0.id, kind: "toolTrace", text: "")
                        }
                    }
                ),
                sequentialStreamingLayoutEnabled: sequentialStreamingLayoutEnabled,
                streamingSegmentTurnIndex: streamingSegmentTurnIndex
            )
        )
        if let next = response?.state {
            return State(
                blocks: next.blocks.map { ReasoningBlock(id: $0.id, text: $0.text) },
                text: next.text,
                segments: next.segments.map { seg in
                    MessageSegment(
                        id: seg.id,
                        kind: {
                            switch seg.kind {
                            case "text": return .text(seg.text)
                            case "toolTrace": return .toolTrace([])
                            default: return .reasoning(seg.text)
                            }
                        }()
                    )
                }
            )
        }
        guard shouldAllowSwiftReasoningFallback(environment: ProcessInfo.processInfo.environment) else {
            return state
        }
        var blocks = state.blocks
        if let idx = blocks.firstIndex(where: { $0.id == groupId }) {
            blocks[idx] = ReasoningBlock(id: groupId, text: output)
        } else {
            blocks.append(ReasoningBlock(id: groupId, text: output))
        }
        return State(blocks: blocks, text: output, segments: state.segments)
    }
}

extension ChatPanelView {
    internal func cliAccountSnapshots(
        for kind: CLIProviderKind
    ) -> [MainChatCLIAccountSnapshotBridge] {
        let cfg = providerFactoryConfig()
        return cliAccountsStore.accounts(for: kind).map { account in
            let executable = switch kind {
            case .codex:
                CLIAccountAuthDetector.resolveExecutable(
                    provider: .codex,
                    providerPath: cfg.codexPath
                )
            case .claude:
                CLIAccountAuthDetector.resolveExecutable(
                    provider: .claude,
                    providerPath: cfg.claudePath
                )
            case .gemini:
                CLIAccountAuthDetector.resolveExecutable(
                    provider: .gemini,
                    providerPath: cfg.geminiCliPath
                )
            }
            let auth = CLIAccountAuthDetector.detect(
                account: account,
                providerPath: executable
            )
            let secret = cliAccountsStore.secret(for: account.id)
            let env = CLIProfileProvisioner.environmentOverrides(
                provider: kind,
                profilePath: account.profilePath,
                secret: secret
            )
            return MainChatCLIAccountSnapshotBridge(
                id: account.id.uuidString,
                provider: account.provider.rawValue,
                label: account.label,
                isEnabled: account.isEnabled,
                isAuthenticated: auth.isLoggedIn,
                priority: account.priority,
                profilePath: account.profilePath,
                envOverrides: env,
                quota: MainChatCLIQuotaSnapshotBridge(account.quota),
                health: MainChatCLIHealthSnapshotBridge(account.health),
                createdAt: account.createdAt,
                updatedAt: account.updatedAt
            )
        }
    }
}
