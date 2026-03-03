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

    internal func shouldHideBuildKickoffMessage(_ message: ChatMessage) -> Bool {
        guard message.role == .assistant else { return false }
        guard suppressedEmptyBuildAssistantMessageIds.contains(message.id) else { return false }
        return message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }


    internal var chatHeader: some View {
        ZStack {
            // Center: Mode tabs — Agent / IDE
            modeTabBar

            // Leading: project + (optional) title, Trailing: rewind button
            HStack(spacing: 8) {
                projectButton
                if shouldShowConversationTitle(headerWidth: chatHeaderWidth) {
                    conversationTitleLabel
                }
                Spacer(minLength: 0)
                rewindButton
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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
    internal var projectButton: some View {
        if let path = effectiveContext.primaryPath {
            Button {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
            } label: {
                Text(effectiveContext.displayLabel)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            .buttonStyle(.plain)
            .help("Open folder \(path)")
        }
    }

    internal var conversationTitleLabel: some View {
        Text(chatStore.conversation(for: conversationId)?.title ?? "New conversation")
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(.primary.opacity(0.7))
            .lineLimit(1)
            .fixedSize()
    }

    internal func shouldShowConversationTitle(headerWidth: CGFloat) -> Bool {
        guard headerWidth >= 760 else { return false }
        let title = chatStore.conversation(for: conversationId)?
            .title
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !title.isEmpty && title != "New conversation"
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
            modeTabButton("Browser", icon: "globe", mode: .browser, color: DesignSystem.Colors.browserColor)
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
        }
        .buttonStyle(.plain)
    }

    // MARK: - Messages Area
    internal var messagesArea: some View {
        // #region agent log
        ScrollViewReader { proxy in
            messagesAreaScrollView(using: proxy)
        }
        .frame(maxWidth: .infinity, minHeight: 120, maxHeight: .infinity)
        .background(
            GeometryReader { g in
                let gw = g.size.width, gh = g.size.height
                if gw < 50 || gh < 50 {
                    let _ = DebugSessionLog.log(
                        location: "ChatPanelView:messagesArea",
                        message: "messagesArea geometry SUSPICIOUS",
                        data: ["width": Double(gw), "height": Double(gh), "msgCount": chatStore.conversation(for: conversationId)?.messages.count ?? 0],
                        hypothesisId: "B"
                    )
                }
                return Color.clear
            }
        )
        .onAppear {
            DebugSessionLog.log(
                location: "ChatPanelView:messagesArea",
                message: "messagesArea onAppear",
                data: ["msgCount": chatStore.conversation(for: conversationId)?.messages.count ?? 0],
                hypothesisId: "B"
            )
        }
        .onDisappear {
            DebugSessionLog.log(
                location: "ChatPanelView:messagesArea",
                message: "messagesArea onDisappear",
                data: ["msgCount": chatStore.conversation(for: conversationId)?.messages.count ?? 0],
                hypothesisId: "B"
            )
        }
        // #endregion
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
        .overlay(messagesAreaEmptyStateOverlay)
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
    }
}
