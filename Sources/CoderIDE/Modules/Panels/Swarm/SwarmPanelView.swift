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

    @State var expandedCardIds: Set<String> = []
    @State var expandedEventIds: Set<UUID> = []
    @State var isFollowingLive = true
    @State var isOrchestratorPopoverPresented = false
    @State var isWorkerPopoverPresented = false

    let topInteractiveInset: CGFloat = 22
    let accent = DesignSystem.Colors.swarmColor

    struct ProviderOption: Identifiable {
        let id: String
        let label: String
    }

    @State var cachedCards: [SwarmLiveCardState] = []
    var sortedCards: [SwarmLiveCardState] { cachedCards }
    var runningCount: Int { cachedCards.filter { $0.status == .running }.count }
    var failedCount: Int { cachedCards.filter { $0.status == .failed }.count }
    var warningCount: Int { cachedCards.reduce(0) { $0 + max(0, $1.warningCount) } }
    var completedCount: Int { cachedCards.filter { $0.status == .completed }.count }
    var liveChangeCount: Int { taskActivityStore.swarmEventsReceivedCount }

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
