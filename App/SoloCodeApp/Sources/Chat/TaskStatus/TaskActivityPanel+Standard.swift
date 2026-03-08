import SwiftUI

extension TaskActivityPanel {
    @ViewBuilder
    internal var standardActivityContent: some View {
        let concreteActivities = scopedConcreteNonSwarmActivities
        let nonSwarmActivities = scopedNonSwarmActivities
        let planTraceActivities = scopedPlanTraceActivities
        let instantGreps = scopedInstantGreps
        let scopedTodos = todoStore.displayTodosForChat(for: conversationId)
        if chatStore.isTaskActive(for: conversationId) {
            liveModeBanner
        }

        // Plan trace
        if coderMode == .plan, !planTraceActivities.isEmpty {
            PlanLiveTraceView(
                activities: planTraceActivities,
                workspaceHints: effectivePrimaryPath.map { [$0] } ?? [],
                onOpenFile: onOpenFile
            )
        }

        // Live activity (expandable)
        if !concreteActivities.isEmpty {
            expandableSection(
                title: "Live activity",
                count: concreteActivities.count,
                icon: "list.bullet.rectangle",
                color: .secondary,
                isExpanded: $isActivitiesExpanded
            ) {
                LiveActivityTimelineView(
                    activities: concreteActivities,
                    maxVisible: 20,
                    workspaceHints: effectivePrimaryPath.map { [$0] } ?? [],
                    onOpenFile: onOpenFile
                )
            }
        }

        // Web Search
        let webActivities = nonSwarmActivities.filter {
            $0.type.hasPrefix("web_search")
        }
        if !webActivities.isEmpty {
            WebSearchLiveView(activities: nonSwarmActivities)
        }

        // Terminals (expandable)
        let terminalActivities = nonSwarmActivities.filter {
            $0.type == "command_execution" || $0.type == "bash"
                || ($0.type == "mcp_tool_call"
                    && ($0.payload["tool"] == "bash" || $0.payload["command"] != nil))
        }
        if !terminalActivities.isEmpty {
            expandableSection(
                title: "Terminals",
                count: terminalActivities.count,
                icon: "terminal",
                color: .secondary,
                isExpanded: $isTerminalsExpanded
            ) {
                ChatTerminalSessionsView(activities: nonSwarmActivities)
            }
        }

        // Instant Grep (expandable)
        if !instantGreps.isEmpty {
            expandableSection(
                title: "Instant Grep",
                count: instantGreps.count,
                icon: "magnifyingglass",
                color: .secondary,
                isExpanded: $isGrepExpanded
            ) {
                InstantGrepCardsView(results: instantGreps) { match in
                    let fullPath: String
                    if (match.file as NSString).isAbsolutePath {
                        fullPath = match.file
                    } else {
                        let basePath = effectivePrimaryPath ?? ""
                        fullPath = (basePath as NSString).appendingPathComponent(match.file)
                    }
                    onOpenFile(fullPath)
                }
            }
        }

        // Todo
        if showTodoSection, !scopedTodos.isEmpty {
            expandableSection(
                title: "Todo",
                count: scopedTodos.count,
                icon: "checklist",
                color: .secondary,
                isExpanded: $isTodoExpanded
            ) {
                TodoLiveInlineCard(
                    store: todoStore,
                    conversationId: conversationId,
                    onOpenFile: onOpenFile
                )
            }
        }

        // Remaining task activities (non-terminal, non-bash)
        let otherActivities = concreteActivities
            .filter {
                $0.type != "command_execution"
                    && $0.type != "bash"
                    && !$0.type.hasPrefix("web_search")
                    && $0.type != "todo_write"
                    && $0.type != "todo_read"
                    && !$0.type.hasPrefix("plan_")
            }
            .suffix(8)
        if !otherActivities.isEmpty {
            ForEach(Array(otherActivities)) { activity in
                TaskActivityRow(activity: activity)
            }
        }
    }
}
