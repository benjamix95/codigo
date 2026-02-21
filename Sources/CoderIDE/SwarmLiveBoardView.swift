import SwiftUI

struct SwarmLiveBoardView: View {
    let cards: [SwarmLiveCardState]
    let isTaskRunning: Bool
    let selectedSwarmId: String?
    let onSelectSwarm: ((String) -> Void)?
    let onSetCollapsed: ((String, Bool) -> Void)?

    @State private var expandedRawIds: Set<UUID> = []
    @State private var isFollowingLive = true
    @State private var localCollapsed: [String: Bool] = [:]

    init(
        cards: [SwarmLiveCardState],
        isTaskRunning: Bool = false,
        selectedSwarmId: String? = nil,
        onSelectSwarm: ((String) -> Void)? = nil,
        onSetCollapsed: ((String, Bool) -> Void)? = nil
    ) {
        self.cards = cards
        self.isTaskRunning = isTaskRunning
        self.selectedSwarmId = selectedSwarmId
        self.onSelectSwarm = onSelectSwarm
        self.onSetCollapsed = onSetCollapsed
    }

    private var visibleCards: [SwarmLiveCardState] {
        cards
    }

    private var liveSignature: String {
        visibleCards
            .map {
                "\($0.swarmId)|\($0.status.rawValue)|\($0.lastEventAt?.timeIntervalSince1970 ?? 0)|\($0.activeOpsCount)|\($0.errorCount)|\($0.recentEvents.count)"
            }
            .joined(separator: ";")
    }

    var body: some View {
        if !visibleCards.isEmpty {
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
                            ForEach(visibleCards) { card in
                                let collapsed = localCollapsed[card.swarmId] ?? card.isCollapsed
                                SwarmLiveCardView(
                                    card: card,
                                    isCollapsed: collapsed,
                                    isSelected: selectedSwarmId == card.swarmId,
                                    expandedRawIds: $expandedRawIds,
                                    onToggleCollapse: {
                                        let next = !collapsed
                                        localCollapsed[card.swarmId] = next
                                        onSetCollapsed?(card.swarmId, next)
                                    },
                                    onSelect: {
                                        onSelectSwarm?(card.swarmId)
                                    }
                                )
                                .id("card-\(card.swarmId)")
                            }
                        }
                    }
                    .simultaneousGesture(DragGesture(minimumDistance: 2).onChanged { _ in
                        isFollowingLive = false
                    })
                    .onAppear {
                        guard isFollowingLive, let last = visibleCards.first?.swarmId else { return }
                        proxy.scrollTo("card-\(last)", anchor: .top)
                    }
                    .onChange(of: liveSignature) { _, _ in
                        guard isFollowingLive, let top = visibleCards.first?.swarmId else { return }
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("card-\(top)", anchor: .top)
                        }
                    }
                }
            }
            .padding(10)
            .background(
                Color(nsColor: .controlBackgroundColor).opacity(0.45),
                in: RoundedRectangle(cornerRadius: 10)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(DesignSystem.Colors.border.opacity(0.7), lineWidth: 0.6)
            )
        }
    }
}

private struct SwarmLiveCardView: View {
    let card: SwarmLiveCardState
    let isCollapsed: Bool
    let isSelected: Bool
    @Binding var expandedRawIds: Set<UUID>
    let onToggleCollapse: () -> Void
    let onSelect: () -> Void

    private let previewEventCount = 12
    private let maxRawPreviewChars = 4096

    private var statusColor: Color {
        switch card.status {
        case .running: return DesignSystem.Colors.warning
        case .failed: return DesignSystem.Colors.error
        case .completed: return DesignSystem.Colors.success
        case .idle: return .secondary
        }
    }

    private var statusLabel: String {
        card.status.rawValue
    }

    private var visibleEvents: [TaskActivity] {
        isCollapsed ? Array(card.recentEvents.suffix(previewEventCount)) : card.recentEvents
    }

    private var elapsedSeconds: Int? {
        guard card.status == .running, let started = card.startedAt else { return nil }
        return max(0, Int(Date().timeIntervalSince(started)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Swarm \(card.swarmId)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                if card.status == .running {
                    ProgressView().controlSize(.mini)
                }
                Text(statusLabel)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(statusColor, in: Capsule())
                if let elapsedSeconds {
                    Text("\(elapsedSeconds)s")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if card.hasUnreadSinceCollapse && isCollapsed {
                    Text("new")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(DesignSystem.Colors.info, in: Capsule())
                }
                Text("ops \(card.activeOpsCount)")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.tertiary)
                if card.errorCount > 0 {
                    Text("err \(card.errorCount)")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(DesignSystem.Colors.error)
                }
                if let last = card.lastEventAt {
                    Text(last.formatted(date: .omitted, time: .standard))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }

            Text("In corso: \(card.currentStepTitle)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if !card.currentDetail.isEmpty {
                Text(card.currentDetail)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }

            if !isCollapsed {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(visibleEvents) { activity in
                        eventRow(activity)
                    }
                }
            }

            HStack {
                Button(isCollapsed ? "Espandi" : "Collassa") {
                    onToggleCollapse()
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.info)
                Spacer()
                if card.status == .completed, let summary = card.summary {
                    Text(summary)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else if card.status == .failed, let err = firstErrorSnippet {
                    Text(err)
                        .font(.system(size: 10))
                        .foregroundStyle(DesignSystem.Colors.error)
                        .lineLimit(2)
                }
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    (isSelected ? DesignSystem.Colors.info : statusColor).opacity(
                        isSelected ? 0.9 : 0.25),
                    lineWidth: isSelected ? 1.2 : 0.8
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture {
            onSelect()
        }
    }

    private var firstErrorSnippet: String? {
        let failed = card.recentEvents.reversed().first {
            let t = $0.title.lowercased()
            let d = ($0.detail ?? "").lowercased()
            return t.contains("errore") || t.contains("failed") || d.contains("errore")
                || d.contains("failed")
        }
        return failed?.detail ?? failed?.title
    }

    @ViewBuilder
    private func eventRow(_ activity: TaskActivity) -> some View {
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
