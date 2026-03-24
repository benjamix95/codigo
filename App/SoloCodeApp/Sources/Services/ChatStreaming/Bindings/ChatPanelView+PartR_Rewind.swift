import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    internal func rewindConversation() {
        guard !isRewinding else { return }
        guard let convId = conversationId,
            let conv = chatStore.conversation(for: convId),
            let lastUserIndex = conv.messages.lastIndex(where: { $0.role == .user })
        else { return }
        let lastUserMessage = conv.messages[lastUserIndex]
        let checkpoint = chatStore.previousCheckpoint(conversationId: convId)
        isRewinding = true

        Task {
            await MainActor.run {
                discardPendingStreamingState(for: convId)
                let didCancelPipeline = pipelineIntegrationService.cancelCurrentJob(for: convId)
                var didCancelTask = didCancelPipeline || cancelRunTask(for: convId)
                if !didCancelTask,
                   activeBuildPlanConversationId == convId,
                   let agentId = activeBuildAgentConversationId {
                    didCancelTask =
                        pipelineIntegrationService.cancelCurrentJob(for: agentId)
                        || cancelRunTask(for: agentId)
                }
                let hasActiveExecution = didCancelTask
                    || chatStore.isTaskActive(for: convId)
                    || pipelineIntegrationService.isRunning(for: convId)
                if hasActiveExecution {
                    switch coderMode {
                    case .codeReviewMultiSwarm:
                        executionController.terminate(scope: .review)
                    case .plan:
                        executionController.terminate(scope: .plan)
                    default:
                        executionController.terminate(scope: .agent)
                    }
                    flowCoordinator.interrupt()
                    finalizeToolTraceTurn(conversationId: convId, outcome: .aborted)
                    snapshotSubagentCardsAndEndTask(conversationId: convId)
                }
            }

            // Try file restore only if we have git snapshots; on error continue
            // with chat-only rewind anyway (always-available behavior).
            if let checkpoint {
                for state in checkpoint.gitStates {
                    do {
                        try checkpointGitStore.restoreSnapshot(
                            ref: state.gitSnapshotRef, gitRoot: state.gitRootPath)
                    } catch {
                        await MainActor.run {
                            appendTechnicalErrorMessage(
                                "[Partial file rewind] \(error.localizedDescription)",
                                in: convId
                            )
                        }
                    }
                }
            }

            await MainActor.run {
                var rewound: Bool
                if let checkpoint {
                    rewound = chatStore.rewindConversationState(
                        to: checkpoint.id, conversationId: convId)
                    if rewound {
                        // Make sure the user message is removed from the chat
                        // (it remains only in the input for editing).
                        rewound = chatStore.rewindConversationToMessageCount(
                            lastUserIndex, conversationId: convId)
                    }
                } else {
                    // Fallback without checkpoint: remove last user turn + response.
                    rewound = chatStore.rewindConversationToMessageCount(
                        lastUserIndex, conversationId: convId)
                }
                guard rewound else {
                    appendTechnicalErrorMessage(
                        "[Rewind error: unable to restore chat state.]", in: convId)
                    isRewinding = false
                    return
                }

                // Cursor-style: bring the last user prompt back into the composer for editing.
                let placeholderImageOnly = "[Attached files]"
                inputText =
                    (lastUserMessage.content == placeholderImageOnly) ? "" : lastUserMessage.content
                attachedComposerAttachments = composerAttachments(from: lastUserMessage)
                isInputFocused = true
                planningState = .idle
                planFlowPhase = .idle
                if shouldResetTaskActivityStoreBeforeStartingTurn(
                    activeTaskConversationIds: chatStore.activeTaskConversationIds,
                    targetConversationId: convId
                ) {
                    clearTaskActivityPipeline()
                }
                swarmProgressStore.clear(conversationId: convId)
                activeBuildPlanConversationId = nil
                activeBuildAgentConversationId = nil
                isRewinding = false
            }
        }
    }

    internal func composerAttachments(from message: ChatMessage) -> [ComposerAttachment] {
        let baseAttachments: [ChatAttachment]
        if let attachments = message.attachments, !attachments.isEmpty {
            baseAttachments = attachments
        } else if let imagePaths = message.imagePaths, !imagePaths.isEmpty {
            baseAttachments = imagePaths.map { path in
                ChatAttachment(
                    kind: .image,
                    originalName: URL(fileURLWithPath: path).lastPathComponent,
                    mimeType: nil,
                    localPath: path
                )
            }
        } else {
            return []
        }

        return baseAttachments.compactMap { item in
            let url = URL(fileURLWithPath: item.localPath)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return ComposerAttachment(
                kind: item.kind,
                url: url,
                originalName: item.originalName,
                mimeType: item.mimeType,
                sizeBytes: item.sizeBytes
            )
        }
    }

    internal func rewindToMessage(at messageIndex: Int, conversationId: UUID) {
        guard !isRewinding else { return }
        guard let conv = chatStore.conversation(for: conversationId),
            messageIndex < conv.messages.count,
            conv.messages[messageIndex].role == .user
        else { return }
        let userMessage = conv.messages[messageIndex]
        let checkpoint = chatStore.checkpoint(forMessageIndex: messageIndex, conversationId: conversationId)
        isRewinding = true

        Task {
            await MainActor.run {
                discardPendingStreamingState(for: conversationId)
                let didCancelPipeline = pipelineIntegrationService.cancelCurrentJob(for: conversationId)
                var didCancelTask = didCancelPipeline || cancelRunTask(for: conversationId)
                if !didCancelTask,
                   activeBuildPlanConversationId == conversationId,
                   let agentId = activeBuildAgentConversationId {
                    didCancelTask =
                        pipelineIntegrationService.cancelCurrentJob(for: agentId)
                        || cancelRunTask(for: agentId)
                }
                let hasActiveExecution = didCancelTask
                    || chatStore.isTaskActive(for: conversationId)
                    || pipelineIntegrationService.isRunning(for: conversationId)
                if hasActiveExecution {
                    switch coderMode {
                    case .codeReviewMultiSwarm:
                        executionController.terminate(scope: .review)
                    case .plan:
                        executionController.terminate(scope: .plan)
                    default:
                        executionController.terminate(scope: .agent)
                    }
                    flowCoordinator.interrupt()
                    finalizeToolTraceTurn(conversationId: conversationId, outcome: .aborted)
                    snapshotSubagentCardsAndEndTask(conversationId: conversationId)
                }
            }

            if let checkpoint {
                for state in checkpoint.gitStates {
                    do {
                        try checkpointGitStore.restoreSnapshot(
                            ref: state.gitSnapshotRef, gitRoot: state.gitRootPath)
                    } catch {
                        await MainActor.run {
                            appendTechnicalErrorMessage(
                                "[Partial file rewind] \(error.localizedDescription)",
                                in: conversationId
                            )
                        }
                    }
                }
            }

            await MainActor.run {
                // Remove the user message from the chat (and everything after it) so it can be
                // edited in the input and resent without duplicates.
                let rewound = chatStore.rewindConversationToMessageCount(
                    messageIndex, conversationId: conversationId)
                guard rewound else {
                    appendTechnicalErrorMessage(
                        "[Rewind error: unable to restore chat state.]", in: conversationId)
                    isRewinding = false
                    return
                }

                let placeholderImageOnly = "[Attached files]"
                inputText =
                    (userMessage.content == placeholderImageOnly) ? "" : userMessage.content
                attachedComposerAttachments = composerAttachments(from: userMessage)
                isInputFocused = true
                planningState = .idle
                planFlowPhase = .idle
                if shouldResetTaskActivityStoreBeforeStartingTurn(
                    activeTaskConversationIds: chatStore.activeTaskConversationIds,
                    targetConversationId: conversationId
                ) {
                    clearTaskActivityPipeline()
                }
                swarmProgressStore.clear(conversationId: conversationId)
                activeBuildPlanConversationId = nil
                activeBuildAgentConversationId = nil
                isRewinding = false
            }
        }
    }

    /// Edit a user message in-place: rewind to that point, replace with
    /// edited text, and auto-send.
    internal func editAndResendMessage(
        editedText: String,
        at messageIndex: Int,
        conversationId: UUID
    ) {
        guard !isRewinding else { return }
        guard let conv = chatStore.conversation(for: conversationId),
              messageIndex < conv.messages.count,
              conv.messages[messageIndex].role == .user
        else { return }

        let checkpoint = chatStore.checkpoint(
            forMessageIndex: messageIndex, conversationId: conversationId)
        isRewinding = true

        Task {
            await MainActor.run {
                discardPendingStreamingState(for: conversationId)
                let didCancelPipeline = pipelineIntegrationService
                    .cancelCurrentJob(for: conversationId)
                var didCancelTask = didCancelPipeline
                    || cancelRunTask(for: conversationId)
                if !didCancelTask,
                   activeBuildPlanConversationId == conversationId,
                   let agentId = activeBuildAgentConversationId
                {
                    didCancelTask =
                        pipelineIntegrationService.cancelCurrentJob(for: agentId)
                        || cancelRunTask(for: agentId)
                }
                if didCancelTask
                    || chatStore.isTaskActive(for: conversationId)
                    || pipelineIntegrationService.isRunning(for: conversationId)
                {
                    executionController.terminate(scope: .agent)
                    flowCoordinator.interrupt()
                    finalizeToolTraceTurn(
                        conversationId: conversationId, outcome: .aborted)
                    snapshotSubagentCardsAndEndTask(
                        conversationId: conversationId)
                }
            }

            if let checkpoint {
                for state in checkpoint.gitStates {
                    try? checkpointGitStore.restoreSnapshot(
                        ref: state.gitSnapshotRef,
                        gitRoot: state.gitRootPath)
                }
            }

            await MainActor.run {
                let rewound = chatStore.rewindConversationToMessageCount(
                    messageIndex, conversationId: conversationId)
                guard rewound else {
                    isRewinding = false
                    return
                }

                planningState = .idle
                planFlowPhase = .idle
                if shouldResetTaskActivityStoreBeforeStartingTurn(
                    activeTaskConversationIds: chatStore
                        .activeTaskConversationIds,
                    targetConversationId: conversationId
                ) {
                    clearTaskActivityPipeline()
                }
                swarmProgressStore.clear(conversationId: conversationId)
                activeBuildPlanConversationId = nil
                activeBuildAgentConversationId = nil
                isRewinding = false

                // Set edited text and send
                inputText = editedText
                handleComposerSend()
            }
        }
    }
}
