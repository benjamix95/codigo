import SwiftUI

extension SubagentChatCardView {
    var headerSection: some View {
        HStack(spacing: 8) {
            Image(systemName: statusIcon)
                .font(.system(size: 14))
                .foregroundStyle(statusIconColor)
                .frame(width: 18, alignment: .center)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(subtitle)
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(.secondary.opacity(0.6))
                    .lineLimit(1)
                    .textShimmer(active: card.status == .running)
            }

            Spacer(minLength: 0)

            if isHovered || isExpanded {
                HStack(spacing: 8) {
                    if card.status == .running, let onStop {
                        Button { onStop() } label: {
                            Text("Stop")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        withAnimation(.snappy(duration: 0.2)) { isExpanded.toggle() }
                    } label: {
                        VStack(spacing: 0.5) {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 6.5, weight: .bold))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 6.5, weight: .bold))
                        }
                        .foregroundStyle(.quaternary)
                        .frame(width: 18, height: 18)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                    .buttonStyle(.plain)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    @ViewBuilder
    var compactSnapshotSection: some View {
        if !isExpanded, let preview = compactPreviewText {
            Divider().opacity(0.1).padding(.horizontal, 12)
            Text(preview)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.secondary.opacity(0.55))
                .lineLimit(3)
                .truncationMode(.tail)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    var expandedSnapshotSection: some View {
        if isExpanded {
            Divider().opacity(0.15).padding(.horizontal, 12)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if !card.liveText.isEmpty {
                            Text(card.liveText.suffix(4000))
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(.primary.opacity(0.7))
                                .textSelection(.enabled)
                                .textShimmer(active: card.status == .running)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                        }

                        if !allEvents.isEmpty {
                            if !card.liveText.isEmpty {
                                Divider().opacity(0.08).padding(.horizontal, 12)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(allEvents) { activity in
                                    eventRow(activity)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }

                        Color.clear.frame(height: 1).id("bottom-anchor")
                    }
                }
                .frame(maxHeight: 280)
                .onChange(of: card.recentEvents.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("bottom-anchor", anchor: .bottom)
                    }
                }
                .onChange(of: card.liveText.count) { _, _ in
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo("bottom-anchor", anchor: .bottom)
                    }
                }
            }
        }
    }

    var title: String {
        card.displayName.isEmpty
            ? SubagentChatCardHelpers.roleDisplayName(from: card.swarmId)
            : card.displayName
    }

    var subtitle: String {
        if card.status == .running {
            if let live = liveRunningSubtitle() { return live }
            return "Working..."
        }
        if card.status == .completed {
            if card.warningCount > 0 { return "Done with warnings" }
            if let summary = card.summary, !summary.isEmpty { return summary }
            return "Done"
        }
        if card.status == .failed { return "Failed" }
        return "Idle"
    }

    var compactPreviewText: String? {
        if card.status == .running {
            let text = card.liveText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let lines = text.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            return lines.suffix(4).joined(separator: "\n")
        }
        return completedResultPreview
    }

    var completedResultPreview: String? {
        guard card.status == .completed || card.status == .failed else { return nil }
        let text = card.liveText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.suffix(6).joined(separator: "\n")
    }

    var statusIcon: String {
        switch card.status {
        case .completed: return card.warningCount > 0 ? "exclamationmark.circle.fill" : "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .running: return "circle.dotted"
        case .idle: return "circle"
        }
    }

    var statusIconColor: Color {
        switch card.status {
        case .completed: return card.warningCount > 0 ? DesignSystem.Colors.warning : .green.opacity(0.7)
        case .failed: return .red.opacity(0.7)
        case .running: return .secondary.opacity(0.5)
        case .idle: return .secondary.opacity(0.3)
        }
    }

    var allEvents: [TaskActivity] {
        card.recentEvents.suffix(40).map { $0 }
    }

    @ViewBuilder
    func eventRow(_ activity: TaskActivity) -> some View {
        let isLast = activity.id == allEvents.last?.id
        HStack(spacing: 6) {
            Image(systemName: eventIcon(for: activity))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(
                    activity.isRunning
                        ? phaseColor(for: activity)
                        : .secondary.opacity(0.5)
                )
                .frame(width: 14, alignment: .center)

            Text(activity.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(activity.isRunning ? Color.primary.opacity(0.8) : Color.secondary.opacity(0.7))
                .lineLimit(1)
                .truncationMode(.tail)
                .textShimmer(active: activity.isRunning && isLast)
        }
        .padding(.vertical, 2)
    }

    func phaseColor(for activity: TaskActivity) -> Color {
        switch activity.phase {
        case .executing: return DesignSystem.Colors.warning
        case .editing: return DesignSystem.Colors.info
        case .searching: return DesignSystem.Colors.swarmColor
        case .planning: return DesignSystem.Colors.planColor
        case .thinking: return DesignSystem.Colors.swarmColor
        }
    }

    func eventIcon(for activity: TaskActivity) -> String {
        switch activity.type {
        case "command_execution", "bash": return "terminal.fill"
        case "file_change", "edit": return "pencil"
        case "mcp_tool_call": return "wrench.and.screwdriver.fill"
        case "web_search", "web_search_started", "web_search_completed": return "magnifyingglass"
        case "web_fetch", "web_fetch_started", "web_fetch_completed": return "globe"
        case "read_batch_started", "read_batch_completed": return "doc.on.doc"
        case "todo_write", "todo_read": return "checklist"
        case "agent": return "person.circle.fill"
        case "subagent_text": return "text.bubble"
        case "reasoning": return "brain"
        default: return "gearshape.fill"
        }
    }

    func liveRunningSubtitle() -> String? {
        let liveDriven = SubagentChatCardHelpers.runningSubtitle(
            detail: card.currentDetail,
            liveText: card.liveText,
            title: title,
            fallback: ""
        )
        if !liveDriven.isEmpty {
            let lower = liveDriven.lowercased()
            if lower != "working..." && lower != "started" {
                return liveDriven
            }
        }

        let candidates: [String?] = [
            card.currentDetail,
            card.recentEvents.last?.detail,
            card.recentEvents.last?.payload["detail"],
            card.recentEvents.last?.title,
            card.currentStepTitle,
            card.recentEvents.last?.payload["query"],
            card.recentEvents.last?.payload["path"],
            card.recentEvents.last?.payload["command"],
            card.recentEvents.last?.payload["tool"],
            card.recentEvents.last?.payload["mcp_tool"],
        ]
        for candidate in candidates {
            if let text = SwarmLivePresentation.normalizedSubtitleText(
                candidate,
                excluding: title
            ) {
                return text
            }
        }
        return nil
    }
}
