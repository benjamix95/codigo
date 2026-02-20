import SwiftUI

struct SwarmLiveBoardView: View {
    let activities: [TaskActivity]
    let isTaskRunning: Bool
    let maxEventsPerLane: Int
    let selectedSwarmId: String?
    let onSelectSwarm: ((String) -> Void)?

    @State private var expandedRawIds: Set<UUID> = []
    @State private var expandedLaneIds: Set<String> = []
    @State private var isFollowingLive = true

    init(
        activities: [TaskActivity],
        isTaskRunning: Bool = false,
        maxEventsPerLane: Int = 120,
        selectedSwarmId: String? = nil,
        onSelectSwarm: ((String) -> Void)? = nil
    ) {
        self.activities = activities
        self.isTaskRunning = isTaskRunning
        self.maxEventsPerLane = max(20, maxEventsPerLane)
        self.selectedSwarmId = selectedSwarmId
        self.onSelectSwarm = onSelectSwarm
    }

    private var laneStates: [SwarmLaneState] {
        TaskActivityStore.laneStates(from: activities, limitPerLane: maxEventsPerLane)
    }

    var body: some View {
        if !laneStates.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Swarm Live")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if isFollowingLive {
                        Label("Live", systemImage: "dot.radiowaves.left.and.right")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(DesignSystem.Colors.info)
                    } else {
                        Button("Torna al live") { isFollowingLive = true }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                    }
                }

                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(laneStates) { lane in
                                SwarmLaneCardView(
                                    lane: lane,
                                    isExpanded: expandedLaneIds.contains(lane.id),
                                    isSelected: selectedSwarmId == lane.swarmId,
                                    expandedRawIds: $expandedRawIds,
                                    onToggleLane: {
                                        if expandedLaneIds.contains(lane.id) {
                                            expandedLaneIds.remove(lane.id)
                                        } else {
                                            expandedLaneIds.insert(lane.id)
                                        }
                                    },
                                    onSelectLane: {
                                        onSelectSwarm?(lane.swarmId)
                                    }
                                )
                                .id("lane-\(lane.id)")
                            }
                        }
                    }
                    .simultaneousGesture(DragGesture(minimumDistance: 2).onChanged { _ in
                        isFollowingLive = false
                    })
                    .onAppear {
                        if isFollowingLive, let last = laneStates.last?.id {
                            proxy.scrollTo("lane-\(last)", anchor: .bottom)
                        }
                    }
                    .onChange(of: activities.count) { _, _ in
                        guard isFollowingLive, let last = laneStates.last?.id else { return }
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("lane-\(last)", anchor: .bottom)
                        }
                    }
                }
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(DesignSystem.Colors.border.opacity(0.7), lineWidth: 0.6)
            )
        }
    }
}

private struct SwarmLaneCardView: View {
    let lane: SwarmLaneState
    let isExpanded: Bool
    let isSelected: Bool
    @Binding var expandedRawIds: Set<UUID>
    let onToggleLane: () -> Void
    let onSelectLane: () -> Void

    private let previewEventCount = 12
    private let maxRawPreviewChars = 4096

    private var visibleEvents: [TaskActivity] {
        let source = lane.events
        return isExpanded ? source : Array(source.suffix(previewEventCount))
    }

    private var statusColor: Color {
        switch lane.status {
        case .running: return DesignSystem.Colors.warning
        case .failed: return DesignSystem.Colors.error
        case .completed: return DesignSystem.Colors.success
        case .idle: return .secondary
        }
    }

    private var statusLabel: String {
        switch lane.status {
        case .running: return "running"
        case .failed: return "failed"
        case .completed: return "completed"
        case .idle: return "idle"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Swarm \(lane.swarmId)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                if lane.status == .running {
                    ProgressView()
                        .controlSize(.mini)
                }
                Text(statusLabel)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(statusColor, in: Capsule())
                Spacer()
                Text("ops \(lane.activeOpsCount)")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.tertiary)
                if lane.errorsCount > 0 {
                    Text("err \(lane.errorsCount)")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(DesignSystem.Colors.error)
                }
                if let last = lane.lastEventAt {
                    Text(last.formatted(date: .omitted, time: .standard))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }

            Text("In corso: \(lane.currentActivityTitle)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(visibleEvents) { activity in
                    laneEventRow(activity)
                }
            }

            HStack {
                if lane.events.count > previewEventCount {
                    Button(isExpanded ? "Mostra meno" : "Mostra cronologia completa") {
                        onToggleLane()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.info)
                }
                Spacer()
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder((isSelected ? DesignSystem.Colors.info : statusColor).opacity(isSelected ? 0.9 : 0.25), lineWidth: isSelected ? 1.2 : 0.8)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture {
            onSelectLane()
        }
    }

    @ViewBuilder
    private func laneEventRow(_ activity: TaskActivity) -> some View {
        let expanded = expandedRawIds.contains(activity.id)
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(activityStatusColor(activity))
                    .frame(width: 6, height: 6)
                Text(activity.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Spacer()
                Text(activity.timestamp.formatted(date: .omitted, time: .standard))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            if let detail = activity.detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(expanded ? nil : 2)
            }

            if let command = activity.payload["command"], !command.isEmpty {
                Text("$ \(command)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(expanded ? nil : 2)
            } else if let path = activity.payload["path"] ?? activity.payload["file"], !path.isEmpty {
                Text(path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let added = activity.payload["linesAdded"] ?? activity.payload["lines_added"],
                   let removed = activity.payload["linesRemoved"] ?? activity.payload["lines_removed"] {
                    Text("+\(added) / -\(removed)")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }

            if hasRaw(activity) {
                Button(expanded ? "Nascondi dettagli" : "Mostra dettagli") {
                    if expanded {
                        expandedRawIds.remove(activity.id)
                    } else {
                        expandedRawIds.insert(activity.id)
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.info)
            }

            if expanded {
                let raw = rawDetail(for: activity)
                if !raw.isEmpty {
                    Text(raw)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
                        .textSelection(.enabled)
                }
                if let diff = activity.payload["diffPreview"], !diff.isEmpty {
                    Text(String(diff.prefix(maxRawPreviewChars)))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func activityStatusColor(_ activity: TaskActivity) -> Color {
        if activity.isRunning { return DesignSystem.Colors.warning }
        let t = activity.type.lowercased()
        if t.contains("failed") || t.contains("error") { return DesignSystem.Colors.error }
        return DesignSystem.Colors.success
    }

    private func hasRaw(_ activity: TaskActivity) -> Bool {
        !(activity.payload["output"] ?? "").isEmpty ||
        !(activity.payload["stderr"] ?? "").isEmpty ||
        !(activity.payload["cwd"] ?? "").isEmpty ||
        !(activity.payload["diffPreview"] ?? "").isEmpty
    }

    private func rawDetail(for activity: TaskActivity) -> String {
        var lines: [String] = []
        if let cwd = activity.payload["cwd"], !cwd.isEmpty {
            lines.append("cwd: \(cwd)")
        }
        if let output = activity.payload["output"], !output.isEmpty {
            lines.append(String(output.prefix(maxRawPreviewChars)))
        }
        if let stderr = activity.payload["stderr"], !stderr.isEmpty {
            lines.append("stderr:")
            lines.append(String(stderr.prefix(maxRawPreviewChars)))
        }
        return lines.joined(separator: "\n\n")
    }
}
