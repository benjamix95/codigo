import SwiftUI

private enum PlanTraceFormatters {
    static let hms: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

private struct PlanTraceItem: Identifiable {
    enum Status {
        case running
        case completed
        case failed

        var label: String {
            switch self {
            case .running: return "running"
            case .completed: return "completed"
            case .failed: return "failed"
            }
        }

        var color: Color {
            switch self {
            case .running: return DesignSystem.Colors.warning
            case .completed: return DesignSystem.Colors.success
            case .failed: return DesignSystem.Colors.error
            }
        }
    }

    let id: UUID
    let icon: String
    let iconColor: Color
    let displayTitle: String
    let displaySummary: String
    let rawOutput: String?
    let timestamp: Date
    let status: Status
    let isExpandable: Bool
    let fileChange: ToolTraceFileChange?

    init(activity: TaskActivity) {
        let mappedFileChange = ToolTraceFileChangeMapper.from(activity: activity)
        id = activity.id
        icon = PlanTraceItem.icon(for: activity.type)
        iconColor = PlanTraceItem.color(for: activity.type)
        displayTitle = PlanTraceItem.title(for: activity, fileChange: mappedFileChange)
        displaySummary = PlanTraceItem.summary(for: activity)
        rawOutput = PlanTraceItem.rawOutput(for: activity)
        timestamp = activity.timestamp
        status = PlanTraceItem.status(for: activity)
        fileChange = mappedFileChange
        isExpandable = mappedFileChange != nil || rawOutput?.isEmpty == false
    }

    private static func title(for activity: TaskActivity, fileChange: ToolTraceFileChange?) -> String {
        if let fileChange {
            return "\(fileChange.kind.displayTitle) \(fileChange.basename)"
        }
        switch activity.type {
        case "command_execution", "bash": return "Running command"
        case "read_batch_started", "read_batch_completed": return "Reading files (batch)"
        case "mcp_tool_call": return "Invoking MCP tool"
        case "web_search", "web_search_started", "web_search_completed", "web_search_failed": return "Web search"
        case "web_fetch", "web_fetch_started", "web_fetch_completed", "web_fetch_failed": return "Fetching page"
        case "process_paused": return "Process paused"
        case "process_resumed": return "Process resumed"
        case "plan_step_update": return "Plan step updated"
        case "debug_phase_update": return "Debug phase"
        case "debug_user_request": return "Debug user request"
        case "debug_resolved": return "Debug resolved"
        case "debug_log": return "Debug log"
        case "debug_query": return "Debug query"
        case "debug_session": return "Debug session"
        case "debug_hypothesize": return "Debug hypothesis"
        case "debug_mark": return "Debug marker"
        case "debug_clean": return "Debug clean"
        case "semantic_search": return "Semantic search"
        case "read_lints": return "Reading diagnostics"
        case "debug_context": return "Debug context"
        default: return activity.title
        }
    }

    private static func summary(for activity: TaskActivity) -> String {
        if let command = activity.payload["command"], !command.isEmpty {
            return command
        }
        if let path = activity.payload["path"] ?? activity.payload["file"], !path.isEmpty {
            return path
        }
        if let query = activity.payload["query"], !query.isEmpty {
            return query
        }
        if let detail = activity.detail, !detail.isEmpty {
            return detail
        }
        return activity.title
    }

    private static func rawOutput(for activity: TaskActivity) -> String? {
        var lines: [String] = []
        if let command = activity.payload["command"], !command.isEmpty {
            lines.append("$ \(command)")
        }
        if let cwd = activity.payload["cwd"], !cwd.isEmpty {
            lines.append("cwd: \(cwd)")
        }
        if let diffPreview = activity.payload["diffPreview"], !diffPreview.isEmpty {
            lines.append("")
            lines.append(diffPreview)
        }
        if let output = activity.payload["output"], !output.isEmpty {
            lines.append("")
            lines.append(output)
        }
        if let stderr = activity.payload["stderr"], !stderr.isEmpty {
            lines.append("")
            lines.append("stderr:")
            lines.append(stderr)
        }
        if lines.isEmpty, let detail = activity.detail, !detail.isEmpty {
            lines.append(detail)
        }
        let joined = lines.joined(separator: "\n")
        return joined.isEmpty ? nil : joined
    }

    private static func status(for activity: TaskActivity) -> Status {
        let normalizedStatus = (activity.payload["status"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if ["failed", "error", "timeout"].contains(normalizedStatus) {
            return .failed
        }
        if ["completed", "done", "success"].contains(normalizedStatus) {
            return .completed
        }

        switch activity.type {
        case "web_search_failed", "web_fetch_failed":
            return .failed
        case "read_batch_completed", "web_search_completed", "web_fetch_completed", "process_resumed", "debug_clean":
            return .completed
        default:
            return activity.isRunning ? .running : .completed
        }
    }

    private static func icon(for type: String) -> String {
        switch type {
        case "command_execution", "bash": return "terminal.fill"
        case "read_batch_started", "read_batch_completed": return "doc.on.doc"
        case "mcp_tool_call": return "wrench.and.screwdriver.fill"
        case "web_search", "web_search_started", "web_search_completed", "web_search_failed": return "magnifyingglass"
        case "web_fetch", "web_fetch_started", "web_fetch_completed", "web_fetch_failed": return "globe"
        case "process_paused": return "pause.circle.fill"
        case "process_resumed": return "play.circle.fill"
        case "plan_step_update": return "list.bullet.rectangle"
        case "debug_phase_update", "debug_user_request", "debug_resolved", "debug_hypothesize": return "ladybug.fill"
        case "debug_log": return "text.badge.plus"
        case "debug_query": return "text.magnifyingglass"
        case "debug_session": return "play.circle.fill"
        case "debug_mark": return "mappin.and.ellipse"
        case "debug_clean": return "trash.fill"
        case "semantic_search": return "brain"
        case "read_lints": return "exclamationmark.triangle.fill"
        case "debug_context": return "list.clipboard.fill"
        case "file_change", "edit": return "doc.text.fill"
        default: return "circle.fill"
        }
    }

    private static func color(for type: String) -> Color {
        switch type {
        case "command_execution", "bash": return DesignSystem.Colors.warning
        case "read_batch_started", "read_batch_completed": return DesignSystem.Colors.agentColor
        case "mcp_tool_call": return DesignSystem.Colors.ideColor
        case "web_search", "web_search_started", "web_search_completed", "web_search_failed": return DesignSystem.Colors.info
        case "web_fetch", "web_fetch_started", "web_fetch_completed", "web_fetch_failed": return DesignSystem.Colors.info
        case "process_paused": return DesignSystem.Colors.warning
        case "process_resumed": return DesignSystem.Colors.success
        case "plan_step_update": return DesignSystem.Colors.planColor
        case "debug_phase_update", "debug_user_request", "debug_resolved", "debug_hypothesize": return DesignSystem.Colors.debugColor
        case "debug_log", "debug_query", "debug_session", "debug_mark", "debug_clean":
            return DesignSystem.Colors.debugColor
        case "semantic_search": return DesignSystem.Colors.info
        case "read_lints": return DesignSystem.Colors.warning
        case "debug_context": return DesignSystem.Colors.debugColor
        case "file_change", "edit": return DesignSystem.Colors.agentColor
        default: return .secondary
        }
    }
}

struct PlanLiveTraceView: View {
    let activities: [TaskActivity]
    let workspaceHints: [String]
    let onOpenFile: ((String) -> Void)?

    @State private var expandedRawById: Set<UUID> = []
    @State private var filePreviewById: [UUID: FileChangePreviewResult] = [:]
    @State private var loadingPreviewIds: Set<UUID> = []

    var body: some View {
        let traceItems = activities.map(PlanTraceItem.init(activity:))
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Plan Live Trace")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(traceItems.count) events")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }

            ForEach(traceItems) { item in
                traceRow(item)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 0.5)
        )
    }

    private func traceRow(_ item: PlanTraceItem) -> some View {
        let isExpanded = expandedRawById.contains(item.id)

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: item.icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(item.iconColor)
                    .frame(width: 14)
                Text(item.displayTitle)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .textShimmer(active: item.status == .running)
                Spacer()

                if let fileChange = item.fileChange {
                    Text("+\(max(0, fileChange.added))")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(DesignSystem.Colors.success)
                    Text("-\(max(0, fileChange.removed))")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(DesignSystem.Colors.error)
                }

                Text(item.status.label)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(item.status.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(item.status.color.opacity(0.12), in: Capsule())
                Text(timestamp(item.timestamp))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            if let fileChange = item.fileChange,
               let path = fileChange.path,
               !path.isEmpty,
               let openPath = FileChangePreviewResolver.resolveOpenPath(for: fileChange, workspaceHints: workspaceHints)
            {
                Button {
                    onOpenFile?(openPath)
                } label: {
                    Text(path)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(DesignSystem.Colors.info)
                        .lineLimit(2)
                }
                .buttonStyle(.plain)
            } else {
                Text(item.displaySummary)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textShimmer(active: item.status == .running)
            }

            if item.isExpandable {
                Button {
                    toggleExpanded(item)
                } label: {
                    Text(isExpanded ? "Hide output" : "Show output")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.info)
                }
                .buttonStyle(.plain)
            }

            if isExpanded {
                if let fileChange = item.fileChange {
                    fileChangePreview(for: fileChange)
                } else if let raw = item.rawOutput {
                    Text(truncated(raw))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Color.black.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func fileChangePreview(for change: ToolTraceFileChange) -> some View {
        if loadingPreviewIds.contains(change.id) {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Loading preview...")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        } else if let preview = filePreviewById[change.id] {
            Text(preview.text)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
                .textSelection(.enabled)
        }
    }

    private func toggleExpanded(_ item: PlanTraceItem) {
        if expandedRawById.contains(item.id) {
            expandedRawById.remove(item.id)
            return
        }

        expandedRawById.insert(item.id)
        if let fileChange = item.fileChange {
            loadPreviewIfNeeded(for: fileChange)
        }
    }

    private func loadPreviewIfNeeded(for change: ToolTraceFileChange) {
        if filePreviewById[change.id] != nil || loadingPreviewIds.contains(change.id) {
            return
        }

        loadingPreviewIds.insert(change.id)
        Task {
            let result = await FileChangePreviewResolver.shared.resolvePreview(
                for: change,
                workspaceHints: workspaceHints
            )
            await MainActor.run {
                filePreviewById[change.id] = result
                loadingPreviewIds.remove(change.id)
            }
        }
    }

    private func timestamp(_ date: Date) -> String {
        PlanTraceFormatters.hms.string(from: date)
    }

    private func truncated(_ text: String, maxChars: Int = 6000) -> String {
        if text.count <= maxChars { return text }
        let end = text.index(text.startIndex, offsetBy: maxChars)
        return String(text[..<end]) + "\n\n... output truncated (\(text.count - maxChars) characters hidden)"
    }
}
