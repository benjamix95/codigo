import SwiftUI

extension SwarmPanelView {
    // MARK: - Detail View

    func detailView(for card: SwarmLiveCardState) -> some View {
        let name = card.formattedTitle
        let backend = backendLabel(for: card)

        let headerSubtitle: String = {
            if card.status == .running {
                return liveSubtitle(for: card) ?? "Working..."
            }
            if card.status == .completed { return card.warningCount > 0 ? "Done with warnings" : "Done" }
            if card.status == .failed { return "Failed" }
            return "Idle"
        }()

        return VStack(spacing: 0) {
            // Back button + header
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.snappy(duration: 0.2)) { selectedSwarmId = nil }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 9, weight: .semibold))
                        Text("All Agents")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(accent)
                }
                .buttonStyle(.plain)

                detailHeaderCard(
                    name: name,
                    backend: backend,
                    subtitle: headerSubtitle,
                    card: card
                )
            }
            .padding(14)

            Divider().opacity(0.2)

            // Sub-agent chat
            SubagentChatView(
                card: card,
                isFollowingLive: isFollowingLive
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Header Card

    @ViewBuilder
    private func detailHeaderCard(
        name: String,
        backend: String?,
        subtitle: String,
        card: SwarmLiveCardState
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if card.status == .running {
                    SpinningDottedCircle()
                } else {
                    Image(systemName: detailStatusIcon(for: card))
                        .font(.system(size: 16))
                        .foregroundStyle(panelStatusAccent(for: card.status))
                }
                Text(name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.7))
                    .lineLimit(2)
            }

            if let backend, !backend.isEmpty {
                Text(backend)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Text(subtitle)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.secondary.opacity(0.6))
                .lineLimit(1)
                .textShimmer(active: card.status == .running)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Task Prompt

    @ViewBuilder
    private func detailTaskPromptSection(card: SwarmLiveCardState) -> some View {
        let taskPrompt = card.taskPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !taskPrompt.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("TASK PROMPT")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.8)
                Text(taskPrompt)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary.opacity(0.78))
                    .textSelection(.enabled)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(accent.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(accent.opacity(0.15), lineWidth: 0.5)
            )
        }
    }

    // MARK: - Chat-like Transcript

    @ViewBuilder
    private func detailTranscriptSection(
        card: SwarmLiveCardState,
        accent: Color,
        proxy: ScrollViewProxy
    ) -> some View {
        if !card.transcript.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("CHAT")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .tracking(0.8)
                    Spacer()
                    if card.status == .running {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(DesignSystem.Colors.swarmColor)
                    }
                    Text("\(card.transcript.count)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.quaternary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }

                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(card.transcript) { entry in
                        detailTranscriptRow(entry, accent: accent)
                            .id("tr-\(entry.id)")
                    }
                }
            }
        } else if !card.liveText.isEmpty {
            let liveOutput = card.liveText.trimmingCharacters(in: .whitespacesAndNewlines)
            VStack(alignment: .leading, spacing: 4) {
                Text(card.status == .running ? "LIVE OUTPUT" : "OUTPUT")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.8)
                Text(String(liveOutput.suffix(4000)))
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.78))
                    .textSelection(.enabled)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.2))
            )
        }
    }

    // MARK: - Transcript Row (chat bubble style)

    @ViewBuilder
    private func detailTranscriptRow(
        _ entry: SubagentTranscriptEntry,
        accent: Color
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: detailTranscriptIcon(entry))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(
                    entry.isRunning ? accent : .secondary.opacity(0.5)
                )
                .frame(width: 16, alignment: .center)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 2) {
                if entry.kind == .activity, !entry.title.isEmpty {
                    HStack(spacing: 4) {
                        Text(entry.title)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.secondary.opacity(0.72))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if let ts = entry.timestamp {
                            Text(ts.formatted(date: .omitted, time: .standard))
                                .font(.system(size: 8.5, design: .monospaced))
                                .foregroundStyle(.quaternary)
                        }
                    }
                }
                if !entry.detail.isEmpty {
                    Text(entry.detail)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.primary.opacity(0.78))
                        .textSelection(.enabled)
                        .textShimmer(active: entry.isRunning)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(entry.kind == .assistantText
                        ? Color(nsColor: .controlBackgroundColor).opacity(0.2)
                        : Color.clear
                    )
            )
        }
    }

    // MARK: - Events Timeline

    @ViewBuilder
    private func detailEventsSection(
        card: SwarmLiveCardState,
        accent: Color
    ) -> some View {
        let events = card.recentEvents
        if !events.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("EVENTS")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .tracking(0.8)
                    Spacer()
                    Text("\(events.count)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.quaternary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }

                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(events) { activity in
                        detailEventRow(activity, accent: accent)
                            .id("det-\(activity.id)")
                    }
                }
            }
        }
    }

    // MARK: - Summary

    @ViewBuilder
    private func detailSummarySection(card: SwarmLiveCardState) -> some View {
        if let summary = card.summary {
            VStack(alignment: .leading, spacing: 4) {
                Text("SUMMARY")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.8)
                Text(summary)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.2))
            )
        }
    }

    // MARK: - Detail Event Row

    @ViewBuilder
    func detailEventRow(_ activity: TaskActivity, accent: Color) -> some View {
        let isExp = expandedEventIds.contains(activity.id)

        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle()
                    .fill(activity.isRunning ? accent : .secondary.opacity(0.5))
                    .frame(width: 5, height: 5)
                Text(activity.title)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(isExp ? nil : 2)
                    .textShimmer(active: activity.isRunning)
                Spacer()
                Text(activity.timestamp.formatted(date: .omitted, time: .standard))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.quaternary)
            }

            if let detail = activity.userFacingDetail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(isExp ? nil : 2)
            }

            if let cmd = activity.payload["command"], !cmd.isEmpty {
                Text("$ \(cmd)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(isExp ? nil : 2)
            } else if let path = activity.payload["path"] ?? activity.payload["file"], !path.isEmpty {
                Text(path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if hasRawDetail(activity) {
                Button(isExp ? "Hide details" : "Show details") {
                    if isExp { expandedEventIds.remove(activity.id) }
                    else { expandedEventIds.insert(activity.id) }
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            }

            if isExp {
                let raw = rawDetail(for: activity)
                if !raw.isEmpty {
                    Text(raw)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.35))
                        )
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
    }

    // MARK: - Icons

    private func detailStatusIcon(for card: SwarmLiveCardState) -> String {
        switch card.status {
        case .running: return "circle.dotted"
        case .completed: return card.warningCount > 0 ? "exclamationmark.circle.fill" : "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .idle: return "circle"
        }
    }

    private func detailTranscriptIcon(_ entry: SubagentTranscriptEntry) -> String {
        if entry.kind == .assistantText { return "text.bubble" }
        let lower = entry.title.lowercased()
        if lower.contains("read") || lower.contains("file") { return "doc.text" }
        if lower.contains("edit") || lower.contains("write") { return "pencil" }
        if lower.contains("search") || lower.contains("grep") || lower.contains("glob") { return "magnifyingglass" }
        if lower.contains("bash") || lower.contains("command") || lower.contains("terminal") { return "terminal.fill" }
        if lower.contains("web") || lower.contains("fetch") { return "globe" }
        if lower.contains("think") || lower.contains("reason") { return "brain" }
        return "gearshape.fill"
    }
}
