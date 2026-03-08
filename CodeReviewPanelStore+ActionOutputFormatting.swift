import CoderEngine
import Foundation

// MARK: - Raw Event Formatting & Enrichment

extension CodeReviewPanelStore {

    func formattedReviewRunEvent(
        type: String,
        payload: [String: String]
    ) -> (sectionTitle: String, line: String)? {
        switch type {
        case "reasoning":
            if let detail = firstNonEmpty([
                payload["detail"], payload["text"], payload["delta"],
                payload["content"], payload["summary"],
            ]) {
                return ("Thinking", detail)
            }
        case "assistant_update":
            if let detail = firstNonEmpty([
                payload["detail"], payload["text"],
                payload["content"], payload["summary"],
            ]) {
                return ("Response", detail)
            }
        case "review-worker-plan":
            let description = firstNonEmpty([
                payload["description"], payload["title"],
            ]) ?? "Planned worker"
            let severity = payload["severity"]
                .map { "[\($0)] " } ?? ""
            let fileCount = payload["fileCount"]
                .map { " (\($0) files)" } ?? ""
            return (
                "Planned Work",
                "- [ ] \(severity)\(description)\(fileCount)"
            )
        case "review-fix-round":
            let round = payload["round"] ?? "?"
            let maxRounds = payload["maxRounds"] ?? "?"
            return ("Progress", "Round \(round)/\(maxRounds)")
        case "review-audit-tool":
            let tool = payload["tool"] ?? "audit"
            let detail = payload["detail"] ?? "completed"
            return ("Audit", "\(tool): \(detail)")
        case "agent":
            let title = payload["title"]
                ?? payload["agent_name"] ?? "agent"
            let detail = payload["detail"]
                ?? payload["status"] ?? "updated"
            return ("Activity", "\(title) — \(detail)")
        case "tool_execution_error", "tool_validation_error":
            let detail = payload["detail"]
                ?? payload["title"] ?? "Tool error"
            return ("Activity", "Error: \(detail)")
        default:
            if let detail = firstNonEmpty([
                payload["detail"],
                payload["title"],
                payload["summary"],
                payload["status"],
                payload["tool"],
                payload["type"],
            ]) {
                return ("Activity", "\(type): \(detail)")
            }
            return ("Activity", type)
        }
        return nil
    }

    func enrichedReviewRawPayload(
        type: String,
        payload: [String: String]
    ) -> [String: String] {
        var enriched = payload
        switch type {
        case "review-worker-plan":
            if let workerId = firstNonEmpty([
                payload["worker_id"], payload["id"],
            ]) {
                enriched["swarm_id"] = workerId
                enriched["group_id"] = payload["group_id"]
                    ?? "swarm-\(workerId)"
                enriched["agent_name"] = payload["agent_name"]
                    ?? workerId
                enriched["title"] = payload["title"]
                    ?? payload["description"] ?? workerId
                if enriched["detail"] == nil {
                    enriched["detail"] = "planned"
                }
            }
        case "review-audit-tool":
            if let tool = firstNonEmpty([payload["tool"]]) {
                let swarmId = "audit-\(tool)"
                enriched["swarm_id"] = swarmId
                enriched["group_id"] = payload["group_id"]
                    ?? "swarm-\(swarmId)"
                enriched["agent_name"] = payload["agent_name"]
                    ?? tool
                enriched["title"] = payload["title"] ?? tool
            }
        case "agent":
            if let swarmId = firstNonEmpty([
                payload["swarm_id"], payload["swarmId"],
            ]) {
                enriched["group_id"] = payload["group_id"]
                    ?? "swarm-\(swarmId)"
                enriched["agent_name"] = payload["agent_name"]
                    ?? payload["title"] ?? swarmId
            }
        default:
            break
        }
        return enriched
    }

    func scopedTaskActivity(
        _ activity: TaskActivity
    ) -> TaskActivity {
        guard let conversationId else { return activity }
        var payload = activity.payload
        payload["conversation_id"] = conversationId
            .uuidString.lowercased()
        return TaskActivity(
            id: activity.id,
            type: activity.type,
            title: activity.title,
            detail: activity.detail,
            payload: payload,
            timestamp: activity.timestamp,
            phase: activity.phase,
            isRunning: activity.isRunning,
            groupId: activity.groupId
        )
    }
}
