import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    internal func downloadCurrentConversationMarkdown() {
        guard let markdown = chatStore.exportConversationMarkdown(conversationId: conversationId) else { return }
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [Self.markdownExportContentType]
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = chatStore.defaultMarkdownFilename(for: conversationId)
        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            do {
                try markdown.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    internal func forkCurrentConversation() {
        guard let newConversationId = chatStore.forkConversation(from: conversationId) else { return }
        selectedConversationId = newConversationId
    }

    internal func shouldHideBuildKickoffMessage(
        _ message: ChatMessage,
        in targetConversationId: UUID?
    ) -> Bool {
        guard message.role == .assistant else { return false }
        guard suppressedEmptyBuildAssistantMessageIds.contains(message.id) else { return false }
        guard message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard let targetConversationId else { return true }

        if activeToolTraceTurnsByConversation[targetConversationId]?.assistantMessageId == message.id {
            return false
        }
        if toolTraceStore.hasTrace(
            conversationId: targetConversationId,
            assistantMessageId: message.id
        ) {
            return false
        }
        if chatStore.isTaskActive(for: targetConversationId),
           let conversation = chatStore.conversation(for: targetConversationId),
           conversation.messages.last(where: { $0.role == .assistant })?.id == message.id {
            return false
        }
        if !todoStore.displayTodosForChat(for: targetConversationId).isEmpty,
           let conversation = chatStore.conversation(for: targetConversationId),
           conversation.messages.last(where: { $0.role == .assistant })?.id == message.id {
            return false
        }
        return true
    }

    /// Lightweight thread context shown inside the chat header,
    /// below the draggable titlebar band.
    internal var chatHeaderInfoBar: some View {
        HStack(spacing: 6) {
            Text(chatTitlebarDisplayTitle)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            chatTitlebarProjectButton

            Spacer()
        }
        .padding(.leading, 6)
        .padding(.trailing, 14)
        .contentShape(Rectangle())
    }

    private var chatTitlebarDisplayTitle: String {
        guard let id = conversationId,
              let conversation = chatStore.conversation(for: id) else {
            return "New thread"
        }
        let raw = conversation.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty || raw == "New conversation" ? "New thread" : raw
    }

    private var chatHeaderLeadingReservedWidth: CGFloat {
        coderMode == .codeReviewMultiSwarm ? 170 : 124
    }

    private var chatHeaderLeadingMaxWidth: CGFloat {
        let availableWidth = ((chatHeaderWidth - chatHeaderLeadingReservedWidth) / 2) - 28
        return max(0, min(320, availableWidth))
    }

    private var shouldHideChatHeaderInfoBar: Bool {
        chatHeaderLeadingMaxWidth < 92
    }

    @ViewBuilder
    private var chatTitlebarProjectButton: some View {
        let path = effectiveContext.primaryPath ?? ""
        let name = effectiveContext.displayLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !path.isEmpty, !name.isEmpty {
            Button {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 9))
                    Text(name)
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Open \(path) in Finder")
        }
    }

    internal var chatHeader: some View {
        modeTabBar
            .frame(maxWidth: .infinity, alignment: .center)
            .overlay(alignment: .leading) {
                headerLeadingBar
            }
            .overlay(alignment: .trailing) {
                rewindButton
            }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(height: 32)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        chatHeaderWidth = proxy.size.width
                    }
                    .onChange(of: proxy.size.width) { _, newWidth in
                        chatHeaderWidth = newWidth
                    }
            }
        )
    }

    @ViewBuilder
    internal var headerLeadingBar: some View {
        chatHeaderInfoBar
            .frame(width: chatHeaderLeadingMaxWidth, alignment: .leading)
            .opacity(shouldHideChatHeaderInfoBar ? 0 : 1)
            .allowsHitTesting(!shouldHideChatHeaderInfoBar)
    }

    internal var rewindButton: some View {
        Button {
            rewindConversation()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 11, weight: .medium))
                if isRewinding {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            .foregroundStyle(
                (chatStore.canRewind(conversationId: conversationId) && !isLoadingForCurrentConversation
                    && !isRewinding) ? .secondary : .quaternary)
        }
        .buttonStyle(.plain)
        .disabled(
            !chatStore.canRewind(conversationId: conversationId) || isLoadingForCurrentConversation
                || isRewinding
        )
        .help("Rewind to previous checkpoint (restore chat and files)")
        .accessibilityLabel("Rewind checkpoint chat")
    }

    // MARK: - Mode Tab Bar (Agent / IDE)

    internal var modeTabBar: some View {
        HStack(spacing: 2) {
            modeTabButton("Agent", icon: "brain", mode: .agent, color: DesignSystem.Colors.agentColor)
            modeTabButton("IDE", icon: "sparkles", mode: .ide, color: DesignSystem.Colors.ideColor)
            if coderMode == .codeReviewMultiSwarm {
                HStack(spacing: 4) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 9, weight: .semibold))
                    Text("Review")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(DesignSystem.Colors.reviewColor)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(DesignSystem.Colors.reviewColor.opacity(0.12), in: Capsule())
            }
        }
    }

    internal func modeTabButton(_ title: String, icon: String, mode: CoderMode, color: Color) -> some View {
        let isSelected = coderMode == mode || (mode == .agent && coderMode == .codeReviewMultiSwarm)
        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                selectMode(mode)
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(isSelected ? color : .secondary.opacity(0.6))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? color.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("chat-mode-tab-\(mode.rawValue.lowercased())")
    }

    // MARK: - Messages Area
    internal var messagesArea: some View {
        ScrollViewReader { proxy in
            ZStack {
                messagesAreaScrollView(using: proxy)
                if shouldShowMessagesAreaEmptyState {
                    messagesAreaEmptyStateOverlay
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    internal func messagesAreaScrollView(using proxy: ScrollViewProxy) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            chatMessagesAreaContent
        }
        .padding(.top, 20)
        .padding(.bottom, 24)
        .frame(maxWidth: chatColumnMaxWidth)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 24)
        .onChange(of: streamContentVersion) { _, _ in
            guard isFollowingLive || isLoadingForCurrentConversation else { return }
            handleStreamContentVersionChange(proxy: proxy)
        }
        .onChange(of: chatStore.conversation(for: conversationId)?.messages.count) { _, _ in
            guard isFollowingLive || isLoadingForCurrentConversation else { return }
            handleMessagesCountChange(proxy: proxy)
        }
        .onChange(of: liveTraceEventCount) { _, _ in
            guard isLoadingForCurrentConversation else { return }
            handleLiveTraceEventsChange(proxy: proxy)
        }
        .onChange(of: planningState) { _, new in
            handlePlanningStateChange(new, proxy: proxy)
        }
        .onChange(of: chatStore.activeTaskConversationIds) { oldSet, newSet in
            handleActiveTaskConversationChange(oldSet: oldSet, newSet: newSet, proxy: proxy)
        }
        .onChange(of: scopedTaskActivityCount) { _, _ in
            guard isLoadingForCurrentConversation else { return }
            handleTaskActivitiesChange(proxy: proxy)
        }
        .onDisappear {
            autoScrollWorkItem?.cancel()
            autoScrollWorkItem = nil
        }
    }
}
