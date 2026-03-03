import Foundation

extension EventNormalizer {
    static func normalizePlanStep(type: String, payload: [String: String]) -> [NormalizedEvent] {
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
                    timestamp: .now,
                    phase: .planning,
                    isRunning: false
                ))
            ]
        }

        let status: PlanStepStatus = {
            if let parsed = PlanStepStatus(rawValue: statusRaw) { return parsed }
            // Handle common LLM aliases
            let normalized = statusRaw
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            switch normalized {
            case "completed", "complete", "finished", "success": return .done
            case "active", "doing", "started", "in_progress", "in-progress": return .running
            case "blocked", "error", "stuck": return .failed
            case "todo", "open", "queued", "waiting": return .pending
            default:
                print("[EventNormalizer] ⚠️ Unknown plan step status '\(statusRaw)', defaulting to .pending")
                return .pending
            }
        }()

        let stepTitle = payload["title"] ?? payload["detail"]
        return [
            .planStepUpdate(stepId: stepId, status: status, title: stepTitle),
            .taskActivity(TaskActivity(
                type: "plan_step_update",
                title: stepTitle ?? "Plan step updated",
                detail: payload["detail"] ?? "Status: \(status.rawValue)",
                payload: payload,
                timestamp: .now,
                phase: .planning,
                isRunning: status == .running,
                groupId: payload["group_id"] ?? stepId
            ))
        ]
    }
}
