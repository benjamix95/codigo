import SwiftUI

extension SubagentChatCardView {
    var headerSection: some View {
        HStack(spacing: 8) {
            statusIconView
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
                    Button {
                        onOpenInPanel()
                    } label: {
                        Text("Apri")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

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
    var taskPromptSection: some View {
        let prompt = card.taskPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !prompt.isEmpty {
            Divider().opacity(0.08).padding(.horizontal, 12)
            VStack(alignment: .leading, spacing: 3) {
                Text("TASK")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.6)
                Text(prompt)
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .lineLimit(isExpanded ? nil : 2)
                    .truncationMode(.tail)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    var compactSnapshotSection: some View {
        if !isExpanded {
            taskPromptSection
            if let preview = compactPreviewText {
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
    }

    @ViewBuilder
    var expandedSnapshotSection: some View {
        if isExpanded {
            Divider().opacity(0.15).padding(.horizontal, 12)
            SubagentChatView(card: card, isFollowingLive: card.status == .running)
                .frame(maxHeight: 320)
        }
    }

    var title: String {
        card.formattedTitle
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
        let transcriptPreview = card.transcript
            .suffix(4)
            .map(\.detail)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        if !transcriptPreview.isEmpty {
            return transcriptPreview
        }
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
        let transcriptPreview = card.transcript
            .suffix(6)
            .map(\.detail)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        if !transcriptPreview.isEmpty {
            return transcriptPreview
        }
        let text = card.liveText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.suffix(6).joined(separator: "\n")
    }

    @ViewBuilder
    var statusIconView: some View {
        if card.status == .running {
            SpinningDottedCircle()
        } else {
            Image(systemName: statusIcon)
                .font(.system(size: 14))
                .foregroundStyle(statusIconColor)
        }
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
