import Foundation
struct SubagentTimeoutError: LocalizedError {
    var errorDescription: String? { "Subagent execution timed out after 5 minutes" }
}

struct SubagentNoMeaningfulEventError: LocalizedError {
    let roleName: String
    let backendName: String
    let timeoutSeconds: Int

    var errorDescription: String? {
        "No live events from \(backendName) for \(roleName) after \(timeoutSeconds)s"
    }
}

actor SubagentExecutionLimiter {
    static let shared = SubagentExecutionLimiter(maxConcurrent: 4)

    private let maxConcurrent: Int
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(maxConcurrent: Int) {
        self.maxConcurrent = max(1, maxConcurrent)
    }

    func acquire() async {
        if running < maxConcurrent {
            running += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
        running += 1
    }

    func release() {
        if !waiters.isEmpty {
            let next = waiters.removeFirst()
            running -= 1
            next.resume()
            return
        }
        running = max(0, running - 1)
    }

    func withPermit<T>(_ operation: () async throws -> T) async rethrows -> T {
        await acquire()
        defer { release() }
        return try await operation()
    }
}

enum SubagentLifecycleStage: String, Sendable {
    case launchingBackend = "launching_backend"
    case waitingFirstEvent = "waiting_first_event"
    case toolActivity = "tool_activity"
    case streamingOutput = "streaming_output"
    case stalled = "stalled"
    case completed = "completed"
    case failed = "failed"
}

enum SubagentLifecycleHealth: String, Sendable {
    case starting
    case waiting
    case active
    case stalled
    case completed
    case failed
}

enum SubagentExecutionRuntimeSettings {
    static var firstMeaningfulEventDeadlineSeconds: TimeInterval = 12
    static var waitingHeartbeatIntervalSeconds: TimeInterval = 1.25
    static var activeHeartbeatIdleSeconds: TimeInterval = 3.5
}

struct SubagentLiveEventContext: Sendable {
    let role: SubagentRole
    let toolName: String
    let toolCallId: String
    let subagentId: String
    let agentName: String
    /// Human-readable display name with spaces (e.g. "Auth Login Flow").
    let readableName: String
    let taskSummary: String
    let backendProviderId: String
    let backendDisplayName: String
    let conversationId: String?

    init(
        role: SubagentRole,
        toolName: String,
        toolCallId: String,
        subagentId: String,
        agentName: String,
        readableName: String = "",
        taskSummary: String,
        backendProviderId: String,
        backendDisplayName: String,
        conversationId: String?
    ) {
        self.role = role
        self.toolName = toolName
        self.toolCallId = toolCallId
        self.subagentId = subagentId
        self.agentName = agentName
        self.readableName = readableName.isEmpty ? agentName : readableName
        self.taskSummary = taskSummary
        self.backendProviderId = backendProviderId
        self.backendDisplayName = backendDisplayName
        self.conversationId = conversationId
    }

    func agentPayload(
        title: String,
        detail: String,
        status: String,
        stage: SubagentLifecycleStage,
        health: SubagentLifecycleHealth,
        phase: String,
        liveEmitted: Bool,
        extra: [String: String] = [:]
    ) -> [String: String] {
        var payload: [String: String] = [
            "title": title,
            "detail": detail,
            "swarm_id": subagentId,
            "group_id": "swarm-\(subagentId)",
            "tool_call_id": toolCallId,
            "agent_name": agentName,
            "readable_name": readableName,
            "task_summary": taskSummary,
            "role": role.rawValue,
            "status": status,
            "phase": phase,
            "subagent_stage": stage.rawValue,
            "subagent_health": health.rawValue,
            "backend_provider_id": backendProviderId,
            "backend_display_name": backendDisplayName,
        ]
        if let conversationId, !conversationId.isEmpty {
            payload["conversation_id"] = conversationId
        }
        if liveEmitted {
            payload["_live_emitted"] = "1"
        }
        for (key, value) in extra where !value.isEmpty {
            payload[key] = value
        }
        return payload
    }

    func textPayload(
        title: String,
        detail: String,
        text: String,
        source: String,
        liveEmitted: Bool
    ) -> [String: String] {
        var payload = agentPayload(
            title: title,
            detail: detail,
            status: "running",
            stage: .streamingOutput,
            health: .active,
            phase: source == "reasoning" ? "thinking" : "executing",
            liveEmitted: liveEmitted,
            extra: [
                "text": text,
                "source": source,
            ]
        )
        payload["backend_provider_id"] = backendProviderId
        payload["backend_display_name"] = backendDisplayName
        return payload
    }

    func enrichRawPayload(
        _ payload: [String: String],
        stage: SubagentLifecycleStage,
        phase: String,
        liveEmitted: Bool
    ) -> [String: String] {
        var enriched = payload
        enriched["swarm_id"] = subagentId
        enriched["group_id"] = "swarm-\(subagentId)"
        enriched["tool_call_id"] = enriched["tool_call_id"] ?? toolCallId
        enriched["agent_name"] = agentName
        if enriched["task_summary"] == nil, !taskSummary.isEmpty {
            enriched["task_summary"] = taskSummary
        }
        enriched["role"] = enriched["role"] ?? role.rawValue
        enriched["phase"] = enriched["phase"] ?? phase
        enriched["subagent_stage"] = stage.rawValue
        enriched["backend_provider_id"] = backendProviderId
        enriched["backend_display_name"] = backendDisplayName
        if let conversationId, !conversationId.isEmpty, enriched["conversation_id"] == nil {
            enriched["conversation_id"] = conversationId
        }
        if liveEmitted {
            enriched["_live_emitted"] = "1"
        }
        return enriched
    }
}
