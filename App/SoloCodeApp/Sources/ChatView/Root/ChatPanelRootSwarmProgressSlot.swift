import SwiftUI

/// Fascia swarm/progress isolata: `ChatPanelView.rootLayout` passa solo dati già snapshot-tati
/// così il body principale non legge `swarmProgressStore` / `taskActivityStore` per la sola visibilità.
struct ChatPanelRootSwarmProgressSlot: View {
    let coderMode: CoderMode
    let swarmSteps: [SwarmStep]
    let swarmCards: [SwarmLiveCardState]
    let pipelineSnapshot: PipelineConversationSnapshot?
    let chromeLoading: Bool
    let activities: [TaskActivity]
    let onSelectSwarm: (String) -> Void

    var body: some View {
        let showStrip =
            coderMode == .agent
            && (!swarmSteps.isEmpty || !swarmCards.isEmpty)
        Group {
            if showStrip {
                SwarmProgressView(
                    steps: swarmSteps,
                    activities: activities,
                    pipelineSnapshot: pipelineSnapshot,
                    isPipelineRunning: pipelineSnapshot?.isRunning == true,
                    isTaskRunning: chromeLoading,
                    onSelectSwarm: onSelectSwarm
                )
            }
        }
    }
}
