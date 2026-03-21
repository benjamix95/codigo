import Foundation

extension TaskActivityPanel {
    internal var scopedActivities: [TaskActivity] {
        taskActivityStore.activities(for: conversationId)
    }

    internal var scopedNonSwarmActivities: [TaskActivity] {
        taskActivityStore.nonSwarmActivities(for: conversationId)
    }

    internal var scopedConcreteNonSwarmActivities: [TaskActivity] {
        taskActivityStore.concreteNonSwarmActivities(for: conversationId)
    }

    internal var scopedPlanTraceActivities: [TaskActivity] {
        taskActivityStore.planRelevantRecentActivities(limit: 20, conversationId: conversationId)
    }

    internal var scopedInstantGreps: [InstantGrepResult] {
        taskActivityStore.instantGreps(for: conversationId)
    }

    internal var hasPlanProgressSignal: Bool {
        scopedActivities.contains { activity in
            let type = normalizedActivityType(activity.type)
            if planExecutionSignalTypes.contains(type) {
                return true
            }
            return planProgressSignalTypes.contains(type)
        }
    }

    internal var hasPlanExecutionSignal: Bool {
        scopedActivities.contains { activity in
            let type = normalizedActivityType(activity.type)
            if planExecutionSignalTypes.contains(type) {
                return true
            }
            guard planStepSignalTypes.contains(type) else {
                return false
            }
            let status = normalizedActivityStatus(activity)
            return status == "running" || status == "in_progress"
        }
    }

    private var planExecutionSignalTypes: Set<String> {
        [
            "command_execution",
            "bash",
            "file_change",
            "edit",
        ]
    }

    private var planStepSignalTypes: Set<String> {
        [
            "plan_step_update",
            "plan_step_upsert",
            "plan_step_batch_update",
        ]
    }

    private var planProgressSignalTypes: Set<String> {
        [
            "plan_step_update",
            "plan_step_upsert",
            "plan_step_batch_update",
            "plan_step_reorder",
            "plan_step_dependency_set",
            "plan_set_walkthrough",
        ]
    }

    private func normalizedActivityType(_ type: String) -> String {
        type
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private func normalizedActivityStatus(_ activity: TaskActivity) -> String {
        let raw = (
            activity.payload["status"]
            ?? activity.payload["detail"]
            ?? activity.detail
            ?? ""
        )
        return raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }
}
