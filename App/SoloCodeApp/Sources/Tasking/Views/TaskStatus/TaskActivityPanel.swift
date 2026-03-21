import SwiftUI

// MARK: - Task Activity Panel (Scrollable, expandable sections)
/// Shows live activities, terminals, grep results, etc. in the messages scroll area.
/// Each section is independently collapsible.

struct TaskActivityPanel: View {
    @ObservedObject var chatStore: ChatStore
    @ObservedObject var taskActivityStore: TaskActivityStore
    @ObservedObject var todoStore: TodoStore

    let conversationId: UUID?
    let coderMode: CoderMode
    let debugPhase: DebugFlowPhase
    let onOpenFile: (String) -> Void
    let effectivePrimaryPath: String?
    let showTodoSection: Bool

    @State var selectedSwarmLaneId: String?
    @State var isActivitiesExpanded = false
    @State var isTerminalsExpanded = false
    @State var isGrepExpanded = false
    @State var isTodoExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            standardActivityContent
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .onChangeCompat(of: chatStore.activeTaskConversationIds) { oldSet, newSet in
            guard let cid = conversationId else { return }
            if oldSet.contains(cid) && !newSet.contains(cid) {
                isActivitiesExpanded = false
                isTerminalsExpanded = false
                isGrepExpanded = false
                isTodoExpanded = false
            }
        }
        .onAppear {
            if selectedSwarmLaneId == nil {
                selectedSwarmLaneId = taskActivityStore.swarmCardStates(for: conversationId).first?.swarmId
            }
        }
        .onChange(of: taskActivityStore.activities.count) { _ in
            let laneStates = taskActivityStore.swarmCardStates(for: conversationId)
            let valid = laneStates.contains { $0.swarmId == selectedSwarmLaneId }
            if !valid {
                selectedSwarmLaneId = laneStates.first?.swarmId
            }
            if selectedSwarmLaneId == nil {
                selectedSwarmLaneId =
                    laneStates.first(where: { $0.status == .running })?.swarmId
                    ?? laneStates.first?.swarmId
            }
        }
    }
}
