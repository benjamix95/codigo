import SwiftUI

struct TerminalActivitySession: Identifiable {
    let id: UUID
    let title: String
    let command: String
    let cwd: String?
    let output: String?
    let stderr: String?
    let timestamp: Date

    init(from activity: TaskActivity) {
        id = activity.id
        title = activity.title
        command = activity.payload["command"] ?? activity.detail ?? activity.title
        cwd = activity.payload["cwd"]
        output = activity.payload["output"]
        stderr = activity.payload["stderr"]
        timestamp = activity.timestamp
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

struct ChatTerminalSessionsView: View {
    let activities: [TaskActivity]
    @State private var expandedSessions: Set<UUID> = []

    private var sessions: [TerminalActivitySession] {
        activities
            .filter { $0.type == "command_execution" || $0.type == "bash" }
            .map(TerminalActivitySession.init(from:))
            .sorted { $0.timestamp > $1.timestamp }
    }

    var body: some View {
        if !sessions.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Terminale in chat")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                ForEach(sessions.prefix(6)) { session in
                    terminalSessionCard(session)
                }
            }
        }
    }

    private func terminalSessionCard(_ session: TerminalActivitySession) -> some View {
        let isExpanded = expandedSessions.contains(session.id)
        let hasOutput = !(session.output?.isEmpty ?? true) || !(session.stderr?.isEmpty ?? true)
        let timeString: String = {
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss"
            return f.string(from: session.timestamp)
        }()

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignSystem.Colors.warning)
                Text("bash")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
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
                    Text("Output non disponibile (il provider non ha restituito stdout/stderr per questo comando).")
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
        case "bash", "command_execution": return "terminal.fill"
        case "search", "web_search", "instant_grep": return "magnifyingglass"
        case "todo_write", "todo_read": return "checklist"
        case "plan_step_update": return "list.bullet.rectangle"
        case "mcp_tool_call": return "wrench.and.screwdriver.fill"
        case "agent": return "ant.fill"
        default: return "circle.fill"
        }
    }

    private var typeColor: Color {
        switch activity.type {
        case "edit", "file_change": return DesignSystem.Colors.agentColor
        case "bash", "command_execution": return DesignSystem.Colors.warning
        case "search", "web_search", "instant_grep": return DesignSystem.Colors.info
        case "todo_write", "todo_read": return .green
        case "plan_step_update": return DesignSystem.Colors.planColor
        case "mcp_tool_call": return DesignSystem.Colors.ideColor
        case "agent": return DesignSystem.Colors.swarmColor
        default: return .secondary
        }
    }

    private var timeString: String {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f.string(from: activity.timestamp)
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
