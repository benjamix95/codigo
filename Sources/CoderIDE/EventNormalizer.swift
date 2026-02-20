import Foundation

struct TodoWritePayload {
    let id: UUID?
    let title: String
    let status: TodoStatus?
    let priority: TodoPriority?
    let notes: String?
    let files: [String]
}

enum NormalizedEvent {
    case taskActivity(TaskActivity)
    case instantGrep(InstantGrepResult)
    case todoWrite(TodoWritePayload)
    case todoRead
    case planStepUpdate(stepId: String, status: PlanStepStatus)
}

enum EventKind: String, Codable {
    case terminalSession = "terminal_session"
    case fileUpdate = "file_update"
    case instantGrep = "instant_grep"
    case todoUpdate = "todo_update"
    case planStepUpdate = "plan_step_update"
    case swarmProgress = "swarm_progress"
    case usageUpdate = "usage_update"
    case errorDiagnostic = "error_diagnostic"
    case generic = "generic"
}

struct NormalizedEventEnvelope {
    let version: Int
    let sourceProvider: String
    let timestamp: Date
    let kind: EventKind
    let payload: [String: String]
    let events: [NormalizedEvent]
}

enum EventNormalizer {
    static func normalizeEnvelope(
        sourceProvider: String,
        type: String,
        payload: [String: String],
        timestamp: Date = .now
    ) -> NormalizedEventEnvelope {
        let events = normalize(type: type, payload: payload, timestamp: timestamp)
        let kind: EventKind
        switch type {
        case "command_execution", "bash": kind = .terminalSession
        case "file_change", "edit": kind = .fileUpdate
        case "reasoning": kind = .generic
        case "instant_grep", "search", "web_search", "web_search_started", "web_search_completed", "web_search_failed": kind = .instantGrep
        case "todo_write", "todo_read": kind = .todoUpdate
        case "plan_step_update": kind = .planStepUpdate
        case "swarm_steps", "agent": kind = .swarmProgress
        case "usage": kind = .usageUpdate
        case "error": kind = .errorDiagnostic
        default: kind = .generic
        }
        return NormalizedEventEnvelope(
            version: 1,
            sourceProvider: sourceProvider,
            timestamp: timestamp,
            kind: kind,
            payload: payload,
            events: events
        )
    }

    static func normalize(type: String, payload: [String: String], timestamp: Date = .now) -> [NormalizedEvent] {
        var events: [NormalizedEvent] = []

        if type == "todo_write", let todo = parseTodoWrite(payload: payload) {
            events.append(.todoWrite(todo))
            return events
        }
        if type == "todo_read" {
            events.append(.todoRead)
            return events
        }
        if type == "plan_step_update",
           let stepId = payload["step_id"],
           let statusRaw = payload["status"],
           let status = PlanStepStatus(rawValue: statusRaw) {
            events.append(.planStepUpdate(stepId: stepId, status: status))
            return events
        }

        if type == "instant_grep", let grep = parseInstantGrep(payload: payload, timestamp: timestamp) {
            events.append(.instantGrep(grep))
            events.append(.taskActivity(TaskActivity(
                type: type,
                title: "Instant Grep • \(grep.query)",
                detail: "\(grep.matchesCount) risultati",
                payload: payload,
                timestamp: timestamp,
                phase: .searching,
                isRunning: false
            )))
            return events
        }

        if (type == "command_execution" || type == "bash"), let grep = parseInstantGrepFromCommand(payload: payload, timestamp: timestamp) {
            events.append(.instantGrep(grep))
        }

        let normalizedType = normalizeSpecialType(type, payload: payload)
        let phase = phaseForType(normalizedType, payload: payload)
        let running = runningStateForType(normalizedType, payload: payload)
        let baseTitle = payload["title"] ?? defaultTitle(for: normalizedType)
        let title = withSwarmPrefix(baseTitle, payload: payload)
        events.append(.taskActivity(TaskActivity(
            type: normalizedType,
            title: title,
            detail: payload["detail"],
            payload: payload,
            timestamp: timestamp,
            phase: phase,
            isRunning: running,
            groupId: payload["group_id"] ?? payload["queryId"] ?? payload["tool_call_id"]
        )))
        return events
    }

    private static func normalizeSpecialType(_ type: String, payload: [String: String]) -> String {
        if type == "web_search",
           let status = payload["status"]?.lowercased() {
            switch status {
            case "started": return "web_search_started"
            case "completed": return "web_search_completed"
            case "failed": return "web_search_failed"
            default: break
            }
        }
        return type
    }

    private static func phaseForType(_ type: String, payload: [String: String]) -> ActivityPhase {
        switch type {
        case "command_execution", "bash":
            return .executing
        case "mcp_tool_call":
            return (payload["tool"] == "bash" || payload["command"] != nil) ? .executing : .thinking
        case "file_change", "edit", "read_batch_started", "read_batch_completed":
            return .editing
        case "instant_grep", "search", "web_search", "web_search_started", "web_search_completed", "web_search_failed":
            return .searching
        case "plan_step_update":
            return .planning
        default:
            return .thinking
        }
    }

    private static func runningStateForType(_ type: String, payload: [String: String]) -> Bool {
        let status = payload["status"]?.lowercased()
        switch type {
        case "command_execution", "bash":
            return status == "started" || status == "running" || status == "in_progress"
        case "mcp_tool_call":
            return status == "started" || status == "running" || status == "in_progress"
        case "agent":
            let detail = payload["detail"]?.lowercased()
            return detail == "started" || status == "started" || status == "running"
        case "web_search_started", "read_batch_started", "process_resumed":
            return true
        case "web_search_completed", "web_search_failed", "read_batch_completed", "process_paused":
            return false
        default:
            return false
        }
    }

    private static func defaultTitle(for type: String) -> String {
        switch type {
        case "process_paused":
            return "Processo in pausa"
        case "process_resumed":
            return "Processo ripreso"
        case "read_batch_started":
            return "Lettura file in batch avviata"
        case "read_batch_completed":
            return "Lettura file in batch completata"
        case "reasoning":
            return "Ragionamento"
        case "web_search_started":
            return "Ricerca web avviata"
        case "web_search_completed":
            return "Ricerca web completata"
        case "web_search_failed":
            return "Ricerca web fallita"
        case "tool_execution_error":
            return "Errore esecuzione tool"
        case "tool_validation_error":
            return "Errore validazione tool"
        case "tool_timeout":
            return "Timeout tool"
        case "permission_denied":
            return "Permesso negato"
        default:
            return type
        }
    }

    private static func withSwarmPrefix(_ title: String, payload: [String: String]) -> String {
        guard let swarmId = payload["swarm_id"]?.trimmingCharacters(in: .whitespacesAndNewlines), !swarmId.isEmpty else {
            return title
        }
        if title.hasPrefix("Swarm \(swarmId)") {
            return title
        }
        return "Swarm \(swarmId) • \(title)"
    }

    private static func parseTodoWrite(payload: [String: String]) -> TodoWritePayload? {
        let title = payload["title"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty else { return nil }
        let id = payload["id"].flatMap(UUID.init(uuidString:))
        let status = payload["status"].flatMap(TodoStatus.init(rawValue:))
        let priority = payload["priority"].flatMap(TodoPriority.init(rawValue:))
        let notes = payload["notes"]
        let files = payload["files"]?.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } ?? []
        return TodoWritePayload(id: id, title: title, status: status, priority: priority, notes: notes, files: files)
    }

    private static func parseInstantGrep(payload: [String: String], timestamp: Date) -> InstantGrepResult? {
        guard let query = payload["query"], !query.isEmpty else { return nil }
        let scope = payload["pathScope"] ?? payload["scope"] ?? "."
        let matchesCount = Int(payload["matchesCount"] ?? "") ?? 0
        let durationMs = Int(payload["duration_ms"] ?? "")
        let preview = payload["previewLines"] ?? ""
        let parsedMatches = parseMatchLines(from: preview)
        return InstantGrepResult(
            query: query,
            scope: scope,
            matchesCount: max(matchesCount, parsedMatches.count),
            durationMs: durationMs,
            matches: parsedMatches,
            createdAt: timestamp
        )
    }

    private static func parseInstantGrepFromCommand(payload: [String: String], timestamp: Date) -> InstantGrepResult? {
        guard let command = payload["command"], command.hasPrefix("rg ") || command.contains(" rg ") else { return nil }
        let query = command
            .split(separator: " ")
            .dropFirst()
            .first
            .map(String.init) ?? "(query)"
        let scope = payload["cwd"] ?? "."
        let output = payload["output"] ?? ""
        let matches = parseMatchLines(from: output)
        guard !matches.isEmpty else { return nil }
        return InstantGrepResult(
            query: query,
            scope: scope,
            matchesCount: matches.count,
            durationMs: nil,
            matches: Array(matches.prefix(30)),
            createdAt: timestamp
        )
    }

    private static func parseMatchLines(from output: String) -> [InstantGrepMatch] {
        let lines = output.split(separator: "\n").map(String.init)
        var matches: [InstantGrepMatch] = []

        for line in lines.prefix(200) {
            let parts = line.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3 else { continue }
            let file = String(parts[0])
            guard let number = Int(parts[1]) else { continue }
            let preview = String(parts[2]).trimmingCharacters(in: .whitespaces)
            matches.append(InstantGrepMatch(file: file, line: number, preview: preview))
        }
        return matches
    }
}
