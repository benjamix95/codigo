import SwiftUI

struct TerminalActivitySession: Identifiable {
    let id: String
    let title: String
    let command: String
    let cwd: String?
    let output: String?
    let stderr: String?
    let timestamp: Date
    let isRunning: Bool
    let sourceActivityId: UUID
    let groupId: String?
    let toolCallId: String?
    let status: String?

    init(
        id: String,
        title: String,
        command: String,
        cwd: String?,
        output: String?,
        stderr: String?,
        timestamp: Date,
        isRunning: Bool,
        sourceActivityId: UUID,
        groupId: String?,
        toolCallId: String?,
        status: String?
    ) {
        self.id = id
        self.title = title
        self.command = command
        self.cwd = cwd
        self.output = output
        self.stderr = stderr
        self.timestamp = timestamp
        self.isRunning = isRunning
        self.sourceActivityId = sourceActivityId
        self.groupId = groupId
        self.toolCallId = toolCallId
        self.status = status
    }

    init(from activity: TaskActivity) {
        sourceActivityId = activity.id
        toolCallId = activity.payload["tool_call_id"]
        groupId = activity.groupId ?? activity.payload["group_id"]
        id = toolCallId ?? groupId ?? activity.id.uuidString
        title = activity.title
        command = activity.payload["command"] ?? activity.detail ?? activity.title
        cwd = activity.payload["cwd"]
        output = activity.payload["output"]
        stderr = activity.payload["stderr"]
        timestamp = activity.timestamp
        isRunning = activity.isRunning
        status = activity.payload["status"]?.lowercased()
    }
}

struct TaskActivityPanelView: View {
    @ObservedObject var store: TaskActivityStore

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(alignment: .leading, spacing: 3) {
                ForEach(store.activities) { activity in
                    TaskActivityRow(activity: activity)
                }
            }
            .padding(8)
        }
        .frame(maxHeight: 120)
        .background(DesignSystem.Colors.backgroundSecondary.opacity(0.5))
        .overlay(alignment: .bottom) {
            Rectangle().fill(DesignSystem.Colors.border).frame(height: 0.5)
        }
    }
}

private enum TimeFormatters {
    static let hms: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

struct ChatTerminalSessionsView: View {
    let activities: [TaskActivity]
    @State private var expandedSessions: Set<String> = []

    private var sessions: [TerminalActivitySession] {
        var byKey: [String: TerminalActivitySession] = [:]
        for activity in activities {
            let isTerminal =
                activity.type == "command_execution" ||
                activity.type == "bash" ||
                (activity.type == "mcp_tool_call" && (activity.payload["tool"] == "bash" || activity.payload["command"] != nil))
            guard isTerminal else { continue }
            let session = TerminalActivitySession(from: activity)
            if let existing = byKey[session.id] {
                byKey[session.id] = merged(existing: existing, incoming: session)
            } else {
                byKey[session.id] = session
            }
        }
        return byKey.values.sorted { $0.timestamp > $1.timestamp }
    }

    private var runningSession: TerminalActivitySession? {
        sessions.first(where: { $0.isRunning || $0.status == "started" || $0.status == "running" || $0.status == "in_progress" })
    }

    var body: some View {
        if !sessions.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Terminale in chat")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                if let running = runningSession {
                    TimelineView(.periodic(from: running.timestamp, by: 1.0)) { context in
                        let elapsed = max(0, Int(context.date.timeIntervalSince(running.timestamp)))
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Running command for \(elapsed)s")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.primary)
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(DesignSystem.Colors.warning.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                ForEach(sessions.prefix(6)) { session in
                    terminalSessionCard(session)
                }
            }
        }
    }

    private func terminalSessionCard(_ session: TerminalActivitySession) -> some View {
        let isExpanded = expandedSessions.contains(session.id)
        let hasOutput = !(session.output?.isEmpty ?? true) || !(session.stderr?.isEmpty ?? true)
        let timeString = TimeFormatters.hms.string(from: session.timestamp)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignSystem.Colors.warning)
                Text("bash")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                if session.isRunning {
                    ProgressView()
                        .controlSize(.mini)
                }
                Text(timeString)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button {
                    if isExpanded { expandedSessions.remove(session.id) } else { expandedSessions.insert(session.id) }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            Text("$ \(session.command)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(isExpanded ? nil : 2)

            if let cwd = session.cwd, !cwd.isEmpty {
                Text(cwd)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            if isExpanded {
                if let output = session.output, !output.isEmpty {
                    ScrollView(.vertical, showsIndicators: true) {
                        Text(output)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 180)
                    .padding(8)
                    .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                }
                if let stderr = session.stderr, !stderr.isEmpty {
                    Text(stderr)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(DesignSystem.Colors.error)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DesignSystem.Colors.error.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        .textSelection(.enabled)
                }
                if !hasOutput {
                    Text(session.isRunning ? "Comando in esecuzione…" : "Output non disponibile (il provider non ha restituito stdout/stderr per questo comando).")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(DesignSystem.Colors.border.opacity(0.8), lineWidth: 0.6)
        )
    }

    private func merged(existing: TerminalActivitySession, incoming: TerminalActivitySession) -> TerminalActivitySession {
        TerminalActivitySession(
            id: existing.id,
            title: incoming.title.isEmpty ? existing.title : incoming.title,
            command: incoming.command.isEmpty ? existing.command : incoming.command,
            cwd: incoming.cwd ?? existing.cwd,
            output: preferLonger(existing.output, incoming.output),
            stderr: preferLonger(existing.stderr, incoming.stderr),
            timestamp: max(existing.timestamp, incoming.timestamp),
            isRunning: incoming.isRunning || (incoming.status == "started" || incoming.status == "running" || incoming.status == "in_progress"),
            sourceActivityId: incoming.sourceActivityId,
            groupId: incoming.groupId ?? existing.groupId,
            toolCallId: incoming.toolCallId ?? existing.toolCallId,
            status: incoming.status ?? existing.status
        )
    }

    private func preferLonger(_ lhs: String?, _ rhs: String?) -> String? {
        let l = lhs ?? ""
        let r = rhs ?? ""
        return r.count >= l.count ? (r.isEmpty ? lhs : r) : lhs
    }
}

struct InstantGrepCardsView: View {
    let results: [InstantGrepResult]
    let onOpenMatch: (InstantGrepMatch) -> Void
    @State private var expandedCards: Set<UUID> = []

    var body: some View {
        if !results.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Instant Grep")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                ForEach(results.prefix(4)) { result in
                    grepCard(result)
                }
            }
        }
    }

    private func grepCard(_ result: InstantGrepResult) -> some View {
        let isExpanded = expandedCards.contains(result.id)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignSystem.Colors.info)
                Text(result.query)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                Spacer()
                Text("\(result.matchesCount) match")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Button {
                    if isExpanded {
                        expandedCards.remove(result.id)
                    } else {
                        expandedCards.insert(result.id)
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
            }
            Text("Scope: \(result.scope)")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            if isExpanded {
                ForEach(result.matches.prefix(8)) { match in
                    Button {
                        onOpenMatch(match)
                    } label: {
                        HStack(alignment: .top, spacing: 6) {
                            Text("\((match.file as NSString).lastPathComponent):\(match.line)")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(DesignSystem.Colors.info)
                            Text(match.preview)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(DesignSystem.Colors.border.opacity(0.8), lineWidth: 0.6)
        )
    }
}

struct TaskActivityRow: View {
    let activity: TaskActivity

    private var typeIcon: String {
        switch activity.type {
        case "edit", "file_change": return "doc.text.fill"
        case "read_batch_started", "read_batch_completed": return "doc.on.doc"
        case "bash", "command_execution": return "terminal.fill"
        case "search", "web_search", "instant_grep", "web_search_started", "web_search_completed", "web_search_failed": return "magnifyingglass"
        case "todo_write", "todo_read": return "checklist"
        case "plan_step_update": return "list.bullet.rectangle"
        case "mcp_tool_call": return "wrench.and.screwdriver.fill"
        case "tool_execution_error", "tool_validation_error", "tool_timeout", "permission_denied": return "exclamationmark.triangle.fill"
        case "process_paused": return "pause.circle.fill"
        case "process_resumed": return "play.circle.fill"
        case "agent": return "ant.fill"
        default: return "circle.fill"
        }
    }

    private var typeColor: Color {
        switch activity.type {
        case "edit", "file_change": return DesignSystem.Colors.agentColor
        case "read_batch_started", "read_batch_completed": return DesignSystem.Colors.agentColor
        case "bash", "command_execution": return DesignSystem.Colors.warning
        case "search", "web_search", "instant_grep", "web_search_started", "web_search_completed", "web_search_failed": return DesignSystem.Colors.info
        case "todo_write", "todo_read": return .green
        case "plan_step_update": return DesignSystem.Colors.planColor
        case "mcp_tool_call": return DesignSystem.Colors.ideColor
        case "tool_execution_error", "tool_validation_error", "tool_timeout", "permission_denied": return DesignSystem.Colors.error
        case "process_paused": return DesignSystem.Colors.warning
        case "process_resumed": return DesignSystem.Colors.success
        case "agent": return DesignSystem.Colors.swarmColor
        default: return .secondary
        }
    }

    private var timeString: String {
        TimeFormatters.hms.string(from: activity.timestamp)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: typeIcon)
                .font(.system(size: 10))
                .foregroundStyle(typeColor)
                .frame(width: 16, alignment: .center)

            VStack(alignment: .leading, spacing: 1) {
                Text(activity.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                if let detail = activity.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(timeString)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
    }
}
