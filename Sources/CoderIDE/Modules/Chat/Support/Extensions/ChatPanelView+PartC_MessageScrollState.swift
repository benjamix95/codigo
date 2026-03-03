import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
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
            if let target = liveScrollTarget() {
                scheduleAutoScroll(proxy: proxy, target: target, delay: 0)
            }
        } else if wasActive && !isActive {
            cancelFallbackTurnStartEvent()
            isFollowingLive = true
            if let target = latestMessageScrollTarget() {
                scheduleAutoScroll(proxy: proxy, target: target, animated: true, delay: 0)
                scheduleAutoScroll(proxy: proxy, target: target, animated: true, delay: 0.16)
            }
        }
    }

    internal func handleTaskActivitiesChange(proxy: ScrollViewProxy) {
        guard isLoadingForCurrentConversation, isFollowingLive else { return }
        if let target = liveScrollTarget() ?? latestMessageScrollTarget() {
            scheduleAutoScroll(proxy: proxy, target: target, delay: 0.08)
        }
    }

    @ViewBuilder
    internal var chatMessagesAreaContent: some View {
        if let conv = chatStore.conversation(for: conversationId) {
            messagesStack(for: conv)
        }
    }
}
