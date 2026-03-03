import SwiftUI
import CoderEngine

struct SwarmPanelView: View {
    @ObservedObject var taskActivityStore: TaskActivityStore
    @ObservedObject var swarmProgressStore: SwarmProgressStore
    @ObservedObject var todoStore: TodoStore
    @ObservedObject var chatStore: ChatStore

    let conversationId: UUID?
    let isTaskRunning: Bool
    @Binding var selectedSwarmId: String?
    @Binding var swarmOrchestrator: String
    @Binding var swarmWorkerBackend: String
    let onClose: () -> Void
    let onOpenFile: (String) -> Void
    let onSyncSwarmProvider: () -> Void

    @State private var expandedCardIds: Set<String> = []
    @State private var expandedEventIds: Set<UUID> = []
    @State private var isFollowingLive = true
    @State private var isOrchestratorPopoverPresented = false
    @State private var isWorkerPopoverPresented = false

    private let topInteractiveInset: CGFloat = 22
    private let accent = DesignSystem.Colors.swarmColor

    private struct ProviderOption: Identifiable {
        let id: String
        let label: String
    }

    @State private var cachedCards: [SwarmLiveCardState] = []
    private var sortedCards: [SwarmLiveCardState] { cachedCards }
    private var runningCount: Int { cachedCards.filter { $0.status == .running }.count }
    private var failedCount: Int { cachedCards.filter { $0.status == .failed }.count }
    private var warningCount: Int { cachedCards.reduce(0) { $0 + max(0, $1.warningCount) } }
    private var completedCount: Int { cachedCards.filter { $0.status == .completed }.count }
    private var liveChangeCount: Int { taskActivityStore.swarmEventsReceivedCount }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: topInteractiveInset)
                .allowsHitTesting(false)

            topBar
            Divider().opacity(0.3)

            if !sortedCards.isEmpty {
                swarmSelector
                Divider().opacity(0.2)
            }

            mainContent

            Divider().opacity(0.2)
            bottomBar
        }
        .background(DesignSystem.Colors.chatPanelSolidBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
        .onAppear {
            isFollowingLive = true
            refreshCachedCards()
            if selectedSwarmId == nil {
                selectedSwarmId = cachedCards.first(where: { $0.status == .running })?.swarmId
            }
        }
        .onChange(of: liveChangeCount) { _, _ in
            refreshCachedCards()
            if let sel = selectedSwarmId,
               !cachedCards.contains(where: { $0.swarmId == sel }) {
                selectedSwarmId = nil
            }
        }
        .onChange(of: isTaskRunning) { _, v in if v { isFollowingLive = true } }
        .onChange(of: conversationId) { _, _ in
            isFollowingLive = true
            expandedCardIds.removeAll()
            expandedEventIds.removeAll()
        }
    }

    func refreshCachedCards() {
        // taskActivityStore.swarmCardStates() is already sorted and cached.
        cachedCards = taskActivityStore.swarmCardStates()
    }
}

