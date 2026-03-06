import Foundation
import os

struct SubagentLiveSnapshot: Sendable {
    let finished: Bool
    let hasMeaningfulEvent: Bool
    let startedAt: Date
    let lastMeaningfulEventAt: Date?
    let currentStage: SubagentLifecycleStage
    let currentDetail: String
    let lastHeartbeatAt: Date?
}

actor SubagentLiveState {
    private let startedAt = Date()
    private var finished = false
    private var hasMeaningfulEvent = false
    private var lastMeaningfulEventAt: Date?
    private var currentStage: SubagentLifecycleStage
    private var currentDetail: String
    private var lastHeartbeatAt: Date?

    init(initialStage: SubagentLifecycleStage, initialDetail: String) {
        currentStage = initialStage
        currentDetail = initialDetail
    }

    func recordMeaningfulEvent(stage: SubagentLifecycleStage, detail: String?) -> Bool {
        let wasFirst = !hasMeaningfulEvent
        hasMeaningfulEvent = true
        lastMeaningfulEventAt = Date()
        currentStage = stage
        if let detail, !detail.isEmpty {
            currentDetail = detail
        }
        return wasFirst
    }

    func update(stage: SubagentLifecycleStage, detail: String?) {
        currentStage = stage
        if let detail, !detail.isEmpty {
            currentDetail = detail
        }
    }

    func markHeartbeat(detail: String) {
        currentStage = hasMeaningfulEvent ? .toolActivity : .waitingFirstEvent
        currentDetail = detail
        lastHeartbeatAt = Date()
    }

    func finish(stage: SubagentLifecycleStage, detail: String?) {
        finished = true
        currentStage = stage
        if let detail, !detail.isEmpty {
            currentDetail = detail
        }
    }

    func snapshot() -> SubagentLiveSnapshot {
        SubagentLiveSnapshot(
            finished: finished,
            hasMeaningfulEvent: hasMeaningfulEvent,
            startedAt: startedAt,
            lastMeaningfulEventAt: lastMeaningfulEventAt,
            currentStage: currentStage,
            currentDetail: currentDetail,
            lastHeartbeatAt: lastHeartbeatAt
        )
    }
}

actor SubagentEventRecorder {
    private var events: [StreamEvent] = []

    func append(_ event: StreamEvent) {
        events.append(event)
    }

    func snapshot() -> [StreamEvent] {
        events
    }
}

enum SubagentPipelineLogger {
    private static let logger = Logger(
        subsystem: "com.codigo.CoderEngine",
        category: "SubagentPipeline"
    )

    static func log(_ message: String) {
        logger.debug("\(message, privacy: .public)")
    }
}

extension ToolEnabledLLMProvider {
    static func subagentOutputLimit(for role: SubagentRole) -> Int {
        switch role {
        case .reviewer, .securityAuditor:
            return 20_000
        default:
            return 8_000
        }
    }

    static func conversationScope(from payload: [String: String]) -> String? {
        let keys = ["conversation_id", "conversationId"]
        for key in keys {
            let value = (payload[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                return value.lowercased()
            }
        }
        return nil
    }

    static func latestMeaningfulLine(in text: String) -> String {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return lines.last ?? String(text.prefix(120))
    }

    static func phaseForSubagentEvent(type: String, payload: [String: String]) -> String {
        let normalizedType = type.lowercased()
        if normalizedType == "reasoning" {
            return "thinking"
        }
        if normalizedType == "file_change" || normalizedType == "edit" {
            return "editing"
        }
        if normalizedType.contains("search") || normalizedType.contains("grep") || normalizedType.contains("read") {
            return "searching"
        }
        return payload["phase"] ?? "executing"
    }

    static func stageForSubagentEvent(type: String, payload: [String: String]) -> SubagentLifecycleStage {
        let normalizedType = type.lowercased()
        if normalizedType == "reasoning" || normalizedType == "subagent_text" {
            return .streamingOutput
        }
        if normalizedType == "tool_execution_error" || normalizedType == "tool_validation_error" || normalizedType == "tool_timeout" {
            return .failed
        }
        let status = (payload["status"] ?? "").lowercased()
        if status == "failed" {
            return .failed
        }
        return .toolActivity
    }

    static func detailForSubagentEvent(type: String, payload: [String: String]) -> String {
        let candidates = [
            payload["detail"],
            payload["title"],
            payload["query"],
            payload["path"],
            payload["command"],
            payload["tool"],
            payload["mcp_tool"],
            payload["name"],
            payload["uri"],
        ]
        for candidate in candidates {
            let text = (candidate ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty {
                return text
            }
        }
        return type.replacingOccurrences(of: "_", with: " ")
    }
}
