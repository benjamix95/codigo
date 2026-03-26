import SwiftUI

/// Fascia swarm/progress isolata: `ChatPanelView.rootLayout` passa solo dati già snapshot-tati
/// così il body principale non legge `swarmProgressStore` / `taskActivityStore` per la sola visibilità.
struct ChatPanelRootSwarmProgressSlot: View {
    let coderMode: CoderMode
    let conversationId: UUID?
    let swarmSteps: [SwarmStep]
    let swarmCards: [SwarmLiveCardState]
    let chromeLoading: Bool
    let activities: [TaskActivity]
    let onSelectSwarm: (String) -> Void
    @ObservedObject var swarmProgressStore: SwarmProgressStore

    var body: some View {
        let showStrip =
            coderMode == .agent
            && (!swarmSteps.isEmpty || !swarmCards.isEmpty)
        Group {
            if showStrip {
                SwarmProgressView(
                    store: swarmProgressStore,
                    activities: activities,
                    conversationId: conversationId,
                    isTaskRunning: chromeLoading,
                    onSelectSwarm: onSelectSwarm
                )
            }
        }
    }
}
