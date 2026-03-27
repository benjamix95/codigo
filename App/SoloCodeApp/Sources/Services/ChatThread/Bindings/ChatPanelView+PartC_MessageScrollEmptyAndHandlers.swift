import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    /// Overlay “vuoto”: un solo punto di decisione con letture coerenti (stesso `conversationId`,
    /// stesso `chatStore`, stesso snapshot). Regola: **mai** coprire l’area se il numero di messaggi
    /// nello store è > 0 **oppure** lo snapshot (allineato o meno) ha ancora righe — la lista
    /// `chatMessagesAreaContent` usa lo snapshot, quindi l’overlay deve rispettarlo. Evidenza H2: log
    /// `empty_state_overlay_shown` con conteggi 4→6 non poteva essere vero nello stesso frame della
    /// decisione (likely desync `onChange` vs `let` sul modifier); questa policy elimina il caso.
    internal var shouldShowMessagesAreaEmptyState: Bool {
        guard !isLoadingForCurrentConversation else { return false }
        // Con zero thread selezionato, lo store non ha contesto: senza questo guard l’overlay
        // “vuoto” si attiva (storeCount 0, snapshot spesso vuoto) e copre tutta l’area. Se
        // `selectedConversationId` vira nil per un frame, effetto “chat sparita” (evidenza
        // fba6fd: empty_overlay_allowed con conversationId nil).
        guard conversationId != nil else { return false }

        let storeCount = chatStore.conversation(for: conversationId)?.messages.count ?? 0
        guard storeCount == 0 else { return false }

        let snap = messagesConversationSnapshot
        let aligned: Bool = {
            guard let cid = conversationId, let s = snap else { return false }
            return s.id == cid
        }()
        let snapCount = snap?.messages.count ?? 0

        if aligned {
            guard snapCount == 0 else { return false }
        } else if let s = snap, !s.messages.isEmpty {
            // Snapshot ancora di un altro thread ma la lista lo sta ancora mostrando: non coprire.
            return false
        }

        let result = true
        return result
    }

    internal var messagesAreaEmptyStateOverlay: some View {
        Text("Ask anything, build anything")
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .offset(y: -40)
            .allowsHitTesting(false)
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
        // Use a longer delay than streamContentVersion (0.04s) so that
        // during streaming, the content version handler handles the scroll
        // and this one gets coalesced by scheduleAutoScroll's throttle.
        // Previously both fired within 10ms of each other with animation,
        // causing duplicate layout passes.
        scheduleAutoScroll(proxy: proxy, target: chatScrollBottomAnchorId, delay: 0.12)
    }

    internal func handleLiveTraceEventsChange(proxy: ScrollViewProxy) {
        guard isLoadingForCurrentConversation, isFollowingLive else { return }
        if let target = liveScrollTarget() {
            // Use a slightly longer delay to let streamContentVersion
            // handle the primary scroll; this acts as a fallback.
            scheduleAutoScroll(proxy: proxy, target: target, delay: 0.14)
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
                // Previously scheduled two overlapping scrolls (0s + 0.16s) with
                // animation. The double schedule raced with other handlers and
                // contributed to main thread saturation. A single delayed scroll
                // is sufficient — the 0.35s throttle in scheduleAutoScroll
                // prevents rapid-fire duplicates.
                scheduleAutoScroll(proxy: proxy, target: target, delay: 0.08)
            }
        }
    }

    internal func handleTaskActivitiesChange(proxy: ScrollViewProxy) {
        guard isLoadingForCurrentConversation, isFollowingLive else { return }
        if let target = liveScrollTarget() ?? latestMessageScrollTarget() {
            scheduleAutoScroll(proxy: proxy, target: target, delay: 0.08)
        }
    }

    /// Lista messaggi: **una** sorgente per `messagesStack` per evitare che SwiftUI alterni due
    /// rami distinti (`if snapshot` vs `else store`) durante refresh → remount e flicker.
    /// Priorità: snapshot solo se `snap.id == conversationId`, altrimenti `chatStore`.
    internal var conversationForMessagesList: Conversation? {
        guard let cid = conversationId else { return nil }
        if let snap = messagesConversationSnapshot, snap.id == cid {
            return snap
        }
        return chatStore.conversation(for: cid)
    }

    @ViewBuilder
    internal var chatMessagesAreaContent: some View {
        if let conv = conversationForMessagesList {
            messagesStack(for: conv)
        } else {
            LazyVStack(alignment: .leading, spacing: 0) {
                Color.clear
                    .frame(height: 1)
                    .id(chatScrollTopAnchorId)
                Color.clear
                    .frame(height: 1)
                    .id(chatScrollBottomAnchorId)
            }
        }
    }
}
