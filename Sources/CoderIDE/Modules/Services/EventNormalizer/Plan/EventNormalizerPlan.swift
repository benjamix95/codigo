import Foundation

extension EventNormalizer {
    static func normalizePlanStep(
        type: String,
        payload: [String: String],
        timestamp: Date
    ) -> [NormalizedEvent] {
        guard
            let stepId = payload["step_id"],
            let statusRaw = payload["status"]
        else {
            return [
                .taskActivity(TaskActivity(
                    type: type,
                    title: type,
                    detail: "Missing plan step payload",
                    payload: payload,
                    timestamp: timestamp,
                    phase: .planning,
                    isRunning: false
                ))
            ]
        }

        guard let status = normalizePlanStepStatus(statusRaw) else {
            return [
                .taskActivity(TaskActivity(
                    type: type,
                    title: type,
                    detail: "Invalid plan step status '\(statusRaw)'",
                    payload: payload,
                    timestamp: timestamp,
                    phase: .planning,
                    isRunning: false
                ))
            ]
        }

        let stepTitle = payload["title"] ?? payload["detail"]
        return [
            .planStepUpdate(stepId: stepId, status: status, title: stepTitle),
            .taskActivity(TaskActivity(
                type: "plan_step_update",
                title: stepTitle ?? "Plan step updated",
                detail: payload["detail"] ?? "Status: \(status.rawValue)",
                payload: payload,
                timestamp: timestamp,
                phase: .planning,
                isRunning: status == .running,
                groupId: payload["group_id"] ?? stepId
            ))
        ]
    }
}
