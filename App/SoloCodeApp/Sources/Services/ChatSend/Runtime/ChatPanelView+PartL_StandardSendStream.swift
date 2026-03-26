import AppKit
import CoderEngine
import os
import SwiftUI
import UniformTypeIdentifiers

private let standardSendStreamLog = Logger(subsystem: "com.solocode.app", category: "ChatSendStream")

extension ChatPanelView {
    /// Stream principale “standard” (Rust transport + UI projection), estratto per riuso dopo screening plan.
    internal func runStandardMainChatSendStream(
        targetConversationId: UUID,
        effectiveRuntimeProvider: any LLMProvider,
        prompt: String,
        shouldRunPlanInline: Bool,
        ctx: WorkspaceContext,
        attachmentsToSend: [LLMAttachment]?
    ) async throws {
        print("[ChatDebug] -> STANDARD mode path (shared helper)")
        let rustAvailable = ReviewCoreBridge.isEnabled
        if !rustAvailable {
            print("[ChatDebug] Rust bridge unavailable — using Swift pipeline fallback for raw events")
        }
        _ = await MainActor.run {
            projectMainChatUISnapshot(conversationId: targetConversationId)
        }
        var streamTextRouteDebugLogged = false
        let streamResult = try await flowCoordinator.runStream(
            provider: effectiveRuntimeProvider,
            prompt: prompt,
            context: ctx,
            attachments: attachmentsToSend,
            onText: { [self] content in
                let cleaned = ChatStore.stripCoderideMarkers(content, aggressive: true)
                let shouldRouteToReasoning = shouldRouteStreamingTextToReasoning(
                    coderMode: coderMode,
                    hasOperationalActivityInTurn: hasOperationalActivityInCurrentTurn(
                        conversationId: targetConversationId
                    ),
                    providerId: effectiveRuntimeProvider.id
                )
                if !streamTextRouteDebugLogged {
                    streamTextRouteDebugLogged = true
                    CursorSessionDebugNDJSON.append(
                        hypothesisId: "H2",
                        location: "ChatPanelView+PartL_StandardSendStream.swift:onText",
                        message: "stream_text_route",
                        data: [
                            "providerId": effectiveRuntimeProvider.id,
                            "routeToReasoning": shouldRouteToReasoning ? "1" : "0",
                            "reasoningSuppressed": ChatReasoningPresentationPolicy.shouldSuppressReasoningUI(
                                messageProviderId: nil,
                                fallbackTurnProviderId: effectiveRuntimeProvider.id
                            ) ? "1" : "0",
                            "cleanedLen": "\(cleaned.count)",
                        ]
                    )
                }
                if standardSendStreamLog.isEnabled(type: .debug) {
                    standardSendStreamLog.debug(
                        "onText len=\(cleaned.count, privacy: .public) routeToReasoning=\(shouldRouteToReasoning, privacy: .public) coderMode=\(String(describing: coderMode), privacy: .public) preview=\(String(cleaned.prefix(80)), privacy: .public)"
                    )
                }
                if shouldRouteToReasoning {
                    applyStreamingReasoningSnapshot(
                        cleaned,
                        conversationId: targetConversationId
                    )
                } else {
                    processInlinePolicyAckMarkers(
                        in: content,
                        providerId: effectiveRuntimeProvider.id,
                        conversationId: targetConversationId
                    )
                    applyMainChatUIStreamIntent(
                        "stream_replace_text",
                        conversationId: targetConversationId,
                        providerId: effectiveRuntimeProvider.id,
                        text: cleaned
                    )
                }
            },
            onRaw: { [self] t, p, pid in
                handleRawStreamEvent(
                    type: t,
                    payload: p,
                    providerId: pid,
                    conversationId: targetConversationId,
                    shouldApplyPipelineArtifacts: true,
                    shouldUpdateInlineReasoningVisuals: true
                )
                if rustAvailable {
                    applyMainChatUIStreamIntent(
                        "stream_apply_raw_event",
                        conversationId: targetConversationId,
                        providerId: pid,
                        payload: ["event_kind": t].merging(p) { _, new in new }
                    )
                }
            },
            onError: { [self] content in
                Task { @MainActor in
                    applyMainChatUIStreamIntent(
                        "stream_finish_failure",
                        conversationId: targetConversationId,
                        providerId: effectiveRuntimeProvider.id,
                        text: content
                    )
                }
            },
            onSignal: nil
        )

        let finalizedResult = try await continueIfPrematureStub(
            initial: streamResult,
            provider: effectiveRuntimeProvider,
            originalPrompt: prompt,
            context: ctx,
            conversationId: targetConversationId,
            hideContentDuringPlanDiscovery: false
        )

        await handleStreamResult(
            conversationId: targetConversationId,
            fullText: finalizedResult,
            shouldRunPlanInline: shouldRunPlanInline,
            ctx: ctx,
            attachmentsToSend: attachmentsToSend,
            prompt: prompt
        )
    }
}
