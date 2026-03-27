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
        var firstVisibleTextLogged = false
        let streamResult = try await flowCoordinator.runStream(
            provider: effectiveRuntimeProvider,
            prompt: prompt,
            context: ctx,
            attachments: attachmentsToSend,
            onText: { [self] content in
                let usesAggressiveStreamingSanitization = effectiveRuntimeProvider.id != "codex-cli"
                let sanitizeStartedAt = CFAbsoluteTimeGetCurrent()
                let cleaned: String
                if usesAggressiveStreamingSanitization {
                    cleaned = ChatStore.stripCoderideMarkers(
                        content,
                        aggressive: true
                    )
                } else {
                    cleaned = ChatStore.stripStreamingCoderideMarkers(content)
                }
                // #region agent log
                RuntimeEvidenceDebugLog.appendThrottled(
                    gateKey: "H40-stream-sanitization-\(targetConversationId.uuidString)",
                    minInterval: 0.08,
                    hypothesisId: "H40",
                    location: "runStandardMainChatSendStream.onText",
                    message: "stream_text_sanitization_profile",
                    data: [
                        "providerId": effectiveRuntimeProvider.id,
                        "conversationId": targetConversationId.uuidString,
                        "aggressive": "\(usesAggressiveStreamingSanitization)",
                        "rawLen": "\(content.count)",
                        "cleanedLen": "\(cleaned.count)",
                    ]
                )
                // #endregion
                let sanitizeMs = Int((CFAbsoluteTimeGetCurrent() - sanitizeStartedAt) * 1000)
                // #region agent log
                RuntimeEvidenceDebugLog.appendThrottled(
                    gateKey: "H41-stream-sanitization-cost-\(targetConversationId.uuidString)",
                    minInterval: 0.08,
                    hypothesisId: "H41",
                    location: "runStandardMainChatSendStream.onText",
                    message: "stream_text_sanitization_cost",
                    data: [
                        "providerId": effectiveRuntimeProvider.id,
                        "conversationId": targetConversationId.uuidString,
                        "path": usesAggressiveStreamingSanitization ? "default_strip" : "swift_streaming_strip",
                        "sanitizeMs": "\(sanitizeMs)",
                        "rawLen": "\(content.count)",
                        "cleanedLen": "\(cleaned.count)",
                    ]
                )
                // #endregion
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
                if !firstVisibleTextLogged, !cleaned.isEmpty {
                    firstVisibleTextLogged = true
                    // #region agent log
                    RuntimeEvidenceDebugLog.append(
                        hypothesisId: "H4",
                        location: "runStandardMainChatSendStream.onText",
                        message: "first_text_callback",
                        data: [
                            "providerId": effectiveRuntimeProvider.id,
                            "cleanedLen": "\(cleaned.count)",
                            "routeToReasoning": "\(shouldRouteToReasoning)",
                            "conversationId": targetConversationId.uuidString,
                        ]
                    )
                    // #endregion
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
                    enqueueMainChatStreamingTextUpdate(
                        cleaned,
                        conversationId: targetConversationId,
                        providerId: effectiveRuntimeProvider.id
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
        // #region agent log
        RuntimeEvidenceDebugLog.append(
            hypothesisId: "H8",
            location: "runStandardMainChatSendStream",
            message: "stream_result_handled",
            data: [
                "providerId": effectiveRuntimeProvider.id,
                "finalizedLen": "\(finalizedResult.count)",
                "conversationId": targetConversationId.uuidString,
            ]
        )
        // #endregion
    }
}
