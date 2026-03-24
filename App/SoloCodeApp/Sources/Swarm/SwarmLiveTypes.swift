import Foundation

enum SwarmCardStatus: String, Codable, Sendable {
    case running
    case completed
    case failed
    case idle
}

/// The kind of entry in a sub-agent's chat transcript.
enum SubagentTranscriptEntryKind: String, Codable, Sendable {
    /// The task/prompt assigned to the sub-agent (shown as "user" message).
    case userPrompt
    /// Reasoning / thinking output from the sub-agent.
    case reasoning
    /// Regular text output from the sub-agent (response).
    case assistantText
    /// A tool call, file read, search, or other operation.
    case activity
    /// A result or completion summary.
    case result
}

struct SubagentTranscriptEntry: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let kind: SubagentTranscriptEntryKind
    let title: String
    let detail: String
    let timestamp: Date?
    let isRunning: Bool

    init(
        id: String = UUID().uuidString.lowercased(),
        kind: SubagentTranscriptEntryKind,
        title: String,
        detail: String,
        timestamp: Date? = nil,
        isRunning: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.timestamp = timestamp
        self.isRunning = isRunning
    }

    /// Creates the opening "user prompt" entry for a sub-agent chat.
    static func userPrompt(_ prompt: String, timestamp: Date?) -> SubagentTranscriptEntry? {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return SubagentTranscriptEntry(
            kind: .userPrompt,
            title: "Task",
            detail: trimmed,
            timestamp: timestamp,
            isRunning: false
        )
    }

    /// Creates a reasoning/thinking entry.
    static func reasoning(_ text: String, timestamp: Date?) -> SubagentTranscriptEntry? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return SubagentTranscriptEntry(
            kind: .reasoning,
            title: "Thinking",
            detail: trimmed,
            timestamp: timestamp,
            isRunning: true
        )
    }

    /// Creates a regular assistant text entry.
    static func assistantText(_ text: String, timestamp: Date?) -> SubagentTranscriptEntry? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return SubagentTranscriptEntry(
            kind: .assistantText,
            title: "Response",
            detail: trimmed,
            timestamp: timestamp,
            isRunning: true
        )
    }

    /// Creates an activity entry from a TaskActivity event.
    /// Filters out raw swarm IDs and technical strings from titles.
    static func activity(_ activity: TaskActivity) -> SubagentTranscriptEntry? {
        var title = activity.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = (activity.detail ?? activity.payload["detail"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty || !detail.isEmpty else { return nil }

        // Clean raw swarm/technical prefixes from title
        title = Self.cleanActivityTitle(title)
        if title.isEmpty { title = Self.humanEventType(activity.type) }

        return SubagentTranscriptEntry(
            kind: .activity,
            title: title,
            detail: detail,
            timestamp: activity.timestamp,
            isRunning: activity.isRunning
        )
    }

    /// Removes raw swarm IDs, tool_use IDs, and "Swarm" prefixes from titles.
    private static func cleanActivityTitle(_ raw: String) -> String {
        var text = raw
        let lower = text.lowercased()

        // Remove "Swarm " prefix followed by swarm_id
        if lower.hasPrefix("swarm ") {
            text = String(text.dropFirst(6)).trimmingCharacters(in: .whitespaces)
        }
        // Remove "sa-XXXX • " prefix
        if let bulletRange = text.range(of: " • ") {
            let prefix = String(text[..<bulletRange.lowerBound]).lowercased()
            if prefix.hasPrefix("sa-") || prefix.contains("toolu_") || prefix.hasPrefix("swarm-") {
                text = String(text[bulletRange.upperBound...])
            }
        }
        // If entire text is a raw ID, return empty
        let lc = text.lowercased()
        if lc.hasPrefix("sa-") || lc.hasPrefix("swarm-") || lc.contains("toolu_") {
            return ""
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    /// Converts raw event type strings to human-readable labels.
    private static func humanEventType(_ type: String) -> String {
        switch type {
        case "agent": return "Agent"
        case "subagent_text": return "Output"
        case "mcp_tool_call": return "Tool Call"
        case "command_execution", "bash": return "Command"
        case "file_change", "edit": return "File Edit"
        case "read_batch_started", "read_batch_completed": return "Read Files"
        case "web_search", "web_search_started": return "Web Search"
        case "reasoning": return "Thinking"
        default: return type.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// Creates a result/completion entry.
    static func result(_ summary: String, timestamp: Date?) -> SubagentTranscriptEntry? {
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return SubagentTranscriptEntry(
            kind: .result,
            title: "Result",
            detail: trimmed,
            timestamp: timestamp,
            isRunning: false
        )
    }
}

struct SwarmLiveCardState: Identifiable, Sendable {
    let swarmId: String
    var displayName: String
    /// The role type of this sub-agent (e.g. "explorer", "coder", "debugger").
    var roleType: String
    /// The original prompt/task assigned to this sub-agent.
    var taskPrompt: String
    var status: SwarmCardStatus
    var startedAt: Date?
    var lastEventAt: Date?
    var completedAt: Date?
    var currentStepTitle: String
    var currentDetail: String
    var activeOpsCount: Int
    var errorCount: Int
    var warningCount: Int
    var recentEvents: [TaskActivity]
    var summary: String?
    var isCollapsed: Bool
    var hasUnreadSinceCollapse: Bool
    /// Accumulated LLM text output streamed in real-time (capped to prevent unbounded growth).
    var liveText: String
    var transcript: [SubagentTranscriptEntry]

    var id: String { swarmId }

    static let liveTextMaxLength = 12_000
    static let transcriptMaxEntries = 120

    /// Human-readable title: "DisplayName - RoleType" format.
    /// Never exposes internal swarm_id.
    var formattedTitle: String {
        let name = displayName.isEmpty ? "Sub Agent" : displayName
        let role = Self.humanRole(roleType)
        if role.isEmpty || name.lowercased() == role.lowercased() {
            return name
        }
        // Don't append role if the name already contains it
        if name.lowercased().contains(role.lowercased()) {
            return name
        }
        return "\(name) - \(role)"
    }

    /// Converts raw role key to human-readable label.
    private static func humanRole(_ raw: String) -> String {
        switch raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
        case "explorer": return "Explorer"
        case "coder": return "Coder"
        case "debugger": return "Debugger"
        case "reviewer": return "Reviewer"
        case "bughunter", "bug_hunter": return "Bug Hunter"
        case "testwriter", "test_writer": return "Test Writer"
        case "docwriter", "doc_writer": return "Doc Writer"
        case "securityauditor", "security_auditor": return "Security Auditor"
        case "agent": return "Agent"
        default: return raw.isEmpty ? "" : raw.capitalized
        }
    }

    init(
        swarmId: String,
        displayName: String = "",
        roleType: String = "",
        taskPrompt: String = "",
        status: SwarmCardStatus = .idle,
        startedAt: Date? = nil,
        lastEventAt: Date? = nil,
        completedAt: Date? = nil,
        currentStepTitle: String = "Awaiting events",
        currentDetail: String = "",
        activeOpsCount: Int = 0,
        errorCount: Int = 0,
        warningCount: Int = 0,
        recentEvents: [TaskActivity] = [],
        summary: String? = nil,
        isCollapsed: Bool = false,
        hasUnreadSinceCollapse: Bool = false,
        liveText: String = "",
        transcript: [SubagentTranscriptEntry] = []
    ) {
        self.swarmId = swarmId
        self.displayName = displayName
        self.roleType = roleType
        self.taskPrompt = taskPrompt
        self.status = status
        self.startedAt = startedAt
        self.lastEventAt = lastEventAt
        self.completedAt = completedAt
        self.currentStepTitle = currentStepTitle
        self.currentDetail = currentDetail
        self.activeOpsCount = activeOpsCount
        self.errorCount = errorCount
        self.warningCount = warningCount
        self.recentEvents = recentEvents
        self.summary = summary
        self.isCollapsed = isCollapsed
        self.hasUnreadSinceCollapse = hasUnreadSinceCollapse
        self.liveText = liveText
        self.transcript = transcript
    }
}
