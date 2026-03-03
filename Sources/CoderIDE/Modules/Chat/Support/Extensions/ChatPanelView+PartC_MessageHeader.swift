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
        false
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
        ScrollViewReader { proxy in
            messagesAreaScrollView(using: proxy)
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
        .simultaneousGesture(
            // Keep this low so trackpad/mouse-wheel scrolling detaches live-follow
            // quickly and prevents forced jumps back to the latest trace event.
            DragGesture(minimumDistance: 2).onChanged { _ in
                if isLoadingForCurrentConversation {
                    isFollowingLive = false
                }
            },
            including: isLoadingForCurrentConversation ? .gesture : .subviews
        )
    }

    @ViewBuilder
    internal var messagesAreaEmptyStateOverlay: some View {
        if messagesAreaIsEmpty && !isLoadingForCurrentConversation {
            VStack(spacing: 20) {
                if let url = Bundle.module.url(forResource: "AppLogo", withExtension: "png"),
                   let icon = NSImage(contentsOf: url) {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 56, height: 56)
                        .cornerRadius(13)
                        .saturation(0)
                        .opacity(0.3)
                }
                VStack(spacing: 6) {
                    Text("codigo")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary.opacity(0.45))
                    Text("Ask anything, build anything")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .offset(y: -40)
            .allowsHitTesting(false)
        }
    }

    internal var messagesAreaIsEmpty: Bool {
        guard let conv = chatStore.conversation(for: conversationId) else { return true }
        return conv.messages.isEmpty
    }

    @ViewBuilder
    internal func messagesAreaFloatingScrollButtons(using proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 8) {
            if !messagesAreaIsEmpty && (!isFollowingLive || isLoadingForCurrentConversation) {
                Button {
                    isFollowingLive = false
                    scheduleAutoScroll(
                        proxy: proxy,
                        target: chatScrollTopAnchorId,
                        animated: true,
                        delay: 0
                    )
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Torna su")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        DesignSystem.Colors.backgroundSecondary.opacity(0.9), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            if !isFollowingLive && isLoadingForCurrentConversation {
                Button {
                    isFollowingLive = true
                    newEventsWhileDetached = 0
                    if let target = liveScrollTarget() {
                        scheduleAutoScroll(proxy: proxy, target: target, animated: true, delay: 0)
                    }
                    taskActivityStore.markLiveEventsSeen()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Back to live")
                            .font(.system(size: 11, weight: .semibold))
                        if newEventsWhileDetached > 0 {
                            Text("\(newEventsWhileDetached)")
                                .font(.system(size: 10, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.white.opacity(0.22), in: Capsule())
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        DesignSystem.Colors.backgroundSecondary.opacity(0.9), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.trailing, 14)
        .padding(.bottom, 10)
    }

    internal func handleStreamContentVersionChange(proxy: ScrollViewProxy) {
        guard isFollowingLive else { return }
        scheduleAutoScroll(proxy: proxy, target: chatScrollBottomAnchorId, delay: 0.04)
    }

    internal func handleMessagesCountChange(proxy: ScrollViewProxy) {
        guard isFollowingLive else { return }
        scheduleAutoScroll(proxy: proxy, target: chatScrollBottomAnchorId, animated: true, delay: 0.05)
    }

    internal func handleLiveTraceEventsChange(proxy: ScrollViewProxy) {
        guard isLoadingForCurrentConversation, isFollowingLive else { return }
        if let target = liveScrollTarget() {
            scheduleAutoScroll(proxy: proxy, target: target, delay: 0.05)
        }
    }

    internal func handlePlanningStateChange(_ newState: PlanningState, proxy: ScrollViewProxy) {
        if case .awaitingChoice = newState {
            if let target = latestMessageScrollTarget() {
                scheduleAutoScroll(proxy: proxy, target: target, animated: true, delay: 0)
            }
        } else if case .awaitingClarification = newState {
            if let target = latestMessageScrollTarget() {
                scheduleAutoScroll(proxy: proxy, target: target, animated: true, delay: 0)
            }
        }
    }

    internal func handleActiveTaskConversationChange(
        oldSet: Set<UUID>,
        newSet: Set<UUID>,
        proxy: ScrollViewProxy
    ) {
        guard let cid = conversationId else { return }
        let isActive = newSet.contains(cid)
        let wasActive = oldSet.contains(cid)
        if !wasActive && isActive {
            isFollowingLive = true
            newEventsWhileDetached = 0
            if let target = liveScrollTarget() {
                scheduleAutoScroll(proxy: proxy, target: target, delay: 0)
            }
        } else if wasActive && !isActive {
            cancelFallbackTurnStartEvent()
            isFollowingLive = true
            newEventsWhileDetached = 0
            if let target = latestMessageScrollTarget() {
                scheduleAutoScroll(proxy: proxy, target: target, animated: true, delay: 0)
                scheduleAutoScroll(proxy: proxy, target: target, animated: true, delay: 0.16)
            }
        }
    }

    internal func handleTaskActivitiesChange(proxy: ScrollViewProxy) {
        if isLoadingForCurrentConversation {
            if isFollowingLive {
                if let target = liveScrollTarget() ?? latestMessageScrollTarget() {
                    scheduleAutoScroll(proxy: proxy, target: target, delay: 0.08)
                }
            } else {
                newEventsWhileDetached += 1
            }
        }
    }

    @ViewBuilder
    internal var chatMessagesAreaContent: some View {
        if let conv = chatStore.conversation(for: conversationId) {
            messagesStack(for: conv)
        }
    }
}
