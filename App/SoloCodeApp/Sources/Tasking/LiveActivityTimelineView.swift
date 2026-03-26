import SwiftUI

private enum LiveTimelineFormatters {
    static let hms: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

struct LiveActivityTimelineView: View {
    let activities: [TaskActivity]
    let maxVisible: Int
    let workspaceHints: [String]
    let onOpenFile: ((String) -> Void)?

    @State private var expandedIds: Set<UUID> = []
    @State private var filePreviewById: [UUID: FileChangePreviewResult] = [:]
    @State private var loadingPreviewIds: Set<UUID> = []

    private var visibleActivities: [TaskActivity] {
        activities
            .filter { TaskActivityStore.isConcreteVisibleEvent($0) }
            .suffix(maxVisible)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(visibleActivities) { activity in
                row(activity)
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.22), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(DesignSystem.Colors.border.opacity(0.45), lineWidth: 0.5)
        )
    }

    private func row(_ activity: TaskActivity) -> some View {
        let expanded = expandedIds.contains(activity.id)
        let fileChange = ToolTraceFileChangeMapper.from(activity: activity)

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Image(systemName: icon(for: activity))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14)

                if let fileChange {
                    Text("\(fileChange.kind.displayTitle) \(fileChange.basename)")
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                } else {
                    Text(activity.title)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                }

                Spacer()

                if let fileChange {
                    Text("+\(max(0, fileChange.added))")
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(DesignSystem.Colors.success)
                    Text("-\(max(0, fileChange.removed))")
                        .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(DesignSystem.Colors.error)
                }

                Text(timestamp(activity.timestamp))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)

                Button {
                    toggleExpanded(activity: activity, fileChange: fileChange)
                } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            if expanded {
                if let detail = activity.userFacingDetail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                if let command = activity.payload["command"], !command.isEmpty {
                    Text("$ \(command)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                }

                if let fileChange {
                    fileChangeExpandedContent(fileChange)
                } else {
                    if let output = activity.payload["output"], !output.isEmpty {
                        Text(output)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(8)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DesignSystem.Colors.border.opacity(0.35))
                .frame(height: 0.5)
        }
    }

    @ViewBuilder
    private func fileChangeExpandedContent(_ change: ToolTraceFileChange) -> some View {
        if let path = change.path, !path.isEmpty {
            if let openPath = FileChangePreviewResolver.resolveOpenPath(for: change, workspaceHints: workspaceHints) {
                Button {
                    onOpenFile?(openPath)
                } label: {
                    Text(path)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(DesignSystem.Colors.info)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
            } else {
                Text(path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }

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
                .lineLimit(nil)
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color(nsColor: .controlBackgroundColor).opacity(0.35),
                    in: RoundedRectangle(cornerRadius: 8)
                )
        }
    }

    private func toggleExpanded(activity: TaskActivity, fileChange: ToolTraceFileChange?) {
        if expandedIds.contains(activity.id) {
            expandedIds.remove(activity.id)
            return
        }
        expandedIds.insert(activity.id)
        if let fileChange {
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

    private func icon(for activity: TaskActivity) -> String {
        switch activity.phase {
        case .executing: return "terminal"
        case .editing: return "pencil"
        case .searching: return "magnifyingglass"
        case .planning: return "list.bullet.rectangle"
        case .thinking: return "gearshape"
        }
    }

    private func timestamp(_ date: Date) -> String {
        LiveTimelineFormatters.hms.string(from: date)
    }
}
