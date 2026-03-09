import SwiftUI

extension PlanPanelView {
    /// Live conversation content while streaming; otherwise planText (local edit buffer).
    /// During multi-turn plan phases, prefer planStreamingContent which is routed directly from the flow.
    var displayPlanContent: String {
        if isEditing { return planText }
        let preferLiveBoard = shouldPreferLivePlanBoardOverHistory(
            phase: planFlowPhase,
            planningState: planningState
        )

        if isPreBuildPlanState {
            if !planStreamingContent.isEmpty {
                return planStreamingContent
            }
            if case .awaitingClarification(let questions) = planningState {
                return questions
            }
            return ""
        }

        if let board = chatStore.planBoard(for: conversationId) {
            if case .awaitingChoice(_, let options) = planningState,
               let preferredOptionContent = preferredPlanPanelOptionContent(
                   chosenPath: board.chosenPath,
                   options: options
               ) {
                return preferredOptionContent
            }
            if let chosen = board.chosenPath?.trimmingCharacters(in: .whitespacesAndNewlines),
               !chosen.isEmpty {
                return chosen
            }
            if let first = firstOption(byId: board.options) {
                return first.fullText
            }
        }

        if !preferLiveBoard, let selected = latestPlanHistoryEntry() {
            return resolvedPreviewContent(for: selected)
        }

        let hasBoard = chatStore.planBoard(for: conversationId) != nil
        let hasSelectedHistoryEntry = latestPlanHistoryEntry() != nil
        let hasContext = hasPlanContext(
            phase: planFlowPhase,
            planningState: planningState,
            hasPlanBoard: hasBoard,
            hasSelectedHistoryEntry: hasSelectedHistoryEntry
        )
        if shouldMirrorAssistantContentInPlanWorkspace(hasPlanContext: hasContext),
           let conv = chatStore.conversation(for: conversationId),
           let last = conv.messages.last(where: { $0.role == .assistant }),
           !last.content.isEmpty
        {
            return last.content
        }
        return planText
    }

    /// Returns a cached snapshot, rebuilding only when plan content or todos actually change.
    /// `snapshotCache` is a reference type (class), so mutating its properties during body
    /// evaluation does NOT trigger a SwiftUI state change — avoiding the runtime warning.
    func resolveSnapshot() -> PlanRenderSnapshot {
        let content = displayPlanContent
        let key = makePlanRenderSnapshotCacheKey(
            content: content,
            canonicalTodos: canonicalPlanTodos
        )
        if key == snapshotCache.key, let cached = snapshotCache.snapshot {
            return cached
        }
        let snapshot = makeRenderSnapshot(content: content)
        snapshotCache.key = key
        snapshotCache.snapshot = snapshot
        return snapshot
    }

    func makeRenderSnapshot(content: String? = nil) -> PlanRenderSnapshot {
        let c = content ?? displayPlanContent
        let planBody = PlanOptionsParser.extractFinalPlanBodyExcludingQuestionsOptionsTodos(c)
        let mermaidBlocks = c.isEmpty ? [] : PlanOptionsParser.extractMermaidBlocksForDisplay(c)
        return PlanRenderSnapshot(
            planContent: c,
            planBodyContent: planBody,
            mermaidBlock: mermaidBlocks.first,
            mermaidBlocks: mermaidBlocks,
            canonicalTodos: canonicalPlanTodos
        )
    }

    func planContentSection(snapshot: PlanRenderSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Plan")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    if isEditing, let convId = conversationId, !planText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        if let board = chatStore.planBoard(for: convId) {
                            let newBoard = PlanBoard.build(from: planText, options: board.options)
                            chatStore.setPlanBoard(newBoard, for: convId)
                        }
                    }
                    if !isEditing {
                        planText = snapshot.planContent
                    }
                    isEditing.toggle()
                } label: {
                    Text(isEditing ? "Done" : "Edit")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(planColor)
                }
                .buttonStyle(.plain)
            }

            if isEditing {
                TextEditor(text: $planText)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 180)
                    .background(
                        Color(nsColor: .controlBackgroundColor).opacity(0.3),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(DesignSystem.Colors.border.opacity(0.4), lineWidth: 0.5)
                    )
            } else if (planFlowPhase == .analyzing || planFlowPhase == .questioning || planFlowPhase == .generating) && isCurrentConversationLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.regular)
                        .scaleEffect(0.8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Analysis in progress")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("Exploring codebase...")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 24)
                .padding(.horizontal, 12)
            } else if !snapshot.planBodyContent.isEmpty {
                MarkdownContentView(
                    content: snapshot.planBodyContent,
                    context: nil,
                    onFileClicked: { _ in },
                    textAlignment: .leading
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .id("workspace-\(planHistoryStore.selectedEntryId?.uuidString ?? "current")-\(historySelectionVersion)")
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 16))
                        .foregroundStyle(.quaternary)
                    Text("Plan content will appear here.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 30)
            }
        }
    }
}
