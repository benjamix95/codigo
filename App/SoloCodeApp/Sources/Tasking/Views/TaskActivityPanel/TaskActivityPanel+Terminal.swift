import SwiftUI

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
        sessions.first(where: \.isRunning)
    }

    private var terminalCardFill: Color { Color(nsColor: .controlBackgroundColor).opacity(0.22) }
    private var terminalCardBorder: Color { Color(nsColor: .separatorColor).opacity(0.45) }
    private var terminalCommandColor: Color { .primary }
    private var terminalHeaderFill: Color { Color(nsColor: .controlBackgroundColor).opacity(0.35) }
    private var terminalAccent: Color { .secondary }
    private var terminalMuted: Color { .secondary }

    var body: some View {
        if !sessions.isEmpty {
            if runningSession != nil {
                liveTerminalCards
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "terminal")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(completedTerminalSummaryLine)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: 860, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .background(
                    Color(nsColor: .controlBackgroundColor).opacity(0.22),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(terminalCardBorder.opacity(0.65), lineWidth: 0.6)
                )
            }
        }
    }

    private var liveTerminalCards: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(terminalAccent)
                Text("Terminale Live")
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("\(sessions.count) session\(sessions.count == 1 ? "" : "i")")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(terminalHeaderFill, in: Capsule())
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(terminalHeaderFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(terminalCardBorder.opacity(0.7), lineWidth: 0.6)
            )

            if let running = runningSession {
                ElapsedTimerView(startDate: running.timestamp) { elapsed in
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Command running")
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                        Text("\(elapsed)s")
                            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.primary)
                            .frame(minWidth: 44, alignment: .trailing)
                        Spacer()
                        Text("LIVE")
                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(terminalAccent)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(terminalAccent.opacity(0.16), in: Capsule())
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(terminalHeaderFill, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .strokeBorder(terminalCardBorder, lineWidth: 0.6)
                    )
                }
            }
            ForEach(sessions.prefix(6)) { session in
                terminalSessionCard(session)
            }
        }
        .padding(10)
        .frame(maxWidth: 860, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
        .background(terminalCardFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(terminalCardBorder.opacity(0.72), lineWidth: 0.7)
        )
    }

    private var completedTerminalSummaryLine: String {
        let completed = sessions.filter { !$0.isRunning }
        guard !completed.isEmpty else { return "No active terminal sessions." }
        let snippets = completed.prefix(3).map { summarizeCommand($0.command) }
        let suffix = completed.count > 3 ? " +\(completed.count - 3) more" : ""
        if completed.count == 1 {
            return "Terminal completed: \(snippets.first ?? "")"
        }
        return "Completed terminals (\(completed.count)): \(snippets.joined(separator: " • "))\(suffix)"
    }

    private func summarizeCommand(_ command: String) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 48 { return trimmed }
        return String(trimmed.prefix(45)) + "..."
    }

    private func terminalSessionCard(_ session: TerminalActivitySession) -> some View {
        let isExpanded = expandedSessions.contains(session.id)
        let hasOutput = !(session.output?.isEmpty ?? true) || !(session.stderr?.isEmpty ?? true)
        let timeString = TaskActivityPanelFormatters.timeFormatter.string(from: session.timestamp)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 10.5))
                    .foregroundStyle(terminalAccent)
                Text("bash")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(terminalMuted)
                if session.isRunning {
                    ProgressView()
                        .controlSize(.mini)
                }
                Text(timeString)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(terminalMuted.opacity(0.85))
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
                .foregroundStyle(terminalCommandColor)
                .lineLimit(isExpanded ? nil : 2)
                .textShimmer(active: session.isRunning)

            if let cwd = session.cwd, !cwd.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "folder")
                        .font(.system(size: 9))
                    Text(cwd)
                        .font(.system(size: 10, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .foregroundStyle(terminalMuted.opacity(0.9))
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
                    .frame(maxHeight: 200)
                    .padding(8)
                    .background(
                        Color(nsColor: .controlBackgroundColor).opacity(0.35),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(terminalCardBorder.opacity(0.5), lineWidth: 0.6)
                    )
                }
                if let stderr = session.stderr, !stderr.isEmpty {
                    Text(stderr)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.red)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        .textSelection(.enabled)
                }
                if !hasOutput {
                    Text(session.isRunning ? "Command running…" : "Output unavailable (the provider did not return stdout/stderr for this command).")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .textShimmer(active: session.isRunning)
                }
            } else if let output = session.output, !output.isEmpty {
                Text(output)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
        }
        .padding(11)
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.28),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(terminalCardBorder, lineWidth: 0.7)
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
            isRunning: incoming.isRunning,
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
