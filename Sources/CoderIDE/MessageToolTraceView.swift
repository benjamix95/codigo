import SwiftUI

struct MessageToolTraceView: View {
    let events: [ToolTraceEvent]

    @State private var expandedIds: Set<UUID> = []

    private var orderedEvents: [ToolTraceEvent] {
        events.sorted { lhs, rhs in
            if lhs.sequence != rhs.sequence { return lhs.sequence < rhs.sequence }
            return lhs.timestamp < rhs.timestamp
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                Text("Tool trace (\(orderedEvents.count) step)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                Spacer(minLength: 0)
            }

            ForEach(orderedEvents) { event in
                traceRow(event)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DesignSystem.Colors.backgroundSecondary.opacity(0.5))
        )
        .frame(maxWidth: 760, alignment: .leading)
    }

    @ViewBuilder
    private func traceRow(_ event: ToolTraceEvent) -> some View {
        let isExpanded = expandedIds.contains(event.id)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                Text("\(event.sequence).")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                    .frame(width: 22, alignment: .leading)

                VStack(alignment: .leading, spacing: 3) {
                    Text(event.title)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(isExpanded ? 3 : 1)
                    if let detail = compactDetail(for: event) {
                        Text(detail)
                            .font(.system(size: 10.5))
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                            .lineLimit(isExpanded ? 4 : 1)
                    }
                }

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    Text(event.isRunning ? "RUN" : "DONE")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(event.isRunning ? DesignSystem.Colors.agentColor : DesignSystem.Colors.textTertiary)
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(DesignSystem.Colors.textQuaternary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isExpanded {
                        expandedIds.remove(event.id)
                    } else {
                        expandedIds.insert(event.id)
                    }
                }
            }
            .padding(.vertical, 6)

            if isExpanded {
                expandedDetails(for: event)
                    .padding(.leading, 30)
                    .padding(.bottom, 6)
            }
        }
    }

    @ViewBuilder
    private func expandedDetails(for event: ToolTraceEvent) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            detailField(label: "Type", value: event.type)
            detailField(label: "Kind", value: event.rawKind)
            if let groupId = event.groupId, !groupId.isEmpty {
                detailField(label: "Group", value: groupId)
            }
            if let command = event.payload["command"], !command.isEmpty {
                detailField(label: "Command", value: command)
            }
            if let query = event.payload["query"], !query.isEmpty {
                detailField(label: "Query", value: query)
            }
            if let path = event.payload["path"] ?? event.payload["file"], !path.isEmpty {
                detailField(label: "Path", value: path)
            }
            if let tool = event.payload["tool"], !tool.isEmpty {
                detailField(label: "Tool", value: tool)
            }
            if let output = event.payload["output"], !output.isEmpty {
                detailField(label: "Output", value: output)
            }
            if let status = event.payload["status"], !status.isEmpty {
                detailField(label: "Status", value: status)
            }
        }
    }

    private func detailField(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.textTertiary)
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .textSelection(.enabled)
                .lineLimit(8)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(DesignSystem.Colors.backgroundTertiary.opacity(0.6))
                )
        }
    }

    private func compactDetail(for event: ToolTraceEvent) -> String? {
        let candidates = [
            event.detail,
            event.payload["command"],
            event.payload["query"],
            event.payload["path"],
            event.payload["file"],
            event.payload["tool"],
        ]
        for candidate in candidates {
            let text = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !text.isEmpty, text != event.title {
                return String(text.prefix(180))
            }
        }
        return nil
    }
}
