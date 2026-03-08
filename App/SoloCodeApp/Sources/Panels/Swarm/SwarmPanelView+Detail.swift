import SwiftUI

extension SwarmPanelView {
    // MARK: - Detail View

    func detailView(for card: SwarmLiveCardState) -> some View {
        let cardAccent = panelStatusAccent(for: card.status)
        let name = panelRoleDisplayName(from: card.swarmId)
        let backend = backendLabel(for: card)

        let headerSubtitle: String = {
            if card.status == .running {
                return liveSubtitle(for: card) ?? "Working..."
            }
            if card.status == .completed { return card.warningCount > 0 ? "Done with warnings" : "Done" }
            if card.status == .failed { return "Failed" }
            return "Idle"
        }()

        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
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

                    VStack(alignment: .leading, spacing: 4) {
                        Text(name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.primary.opacity(0.7))
                            .lineLimit(2)

                        if let backend, !backend.isEmpty {
                            Text(backend)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }

                        Text(headerSubtitle)
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

                    if !card.currentDetail.isEmpty {
                        Text(card.currentDetail)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.2))
                            )
                    }

                    let liveOutput = card.liveText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !liveOutput.isEmpty {
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
                                    detailEventRow(activity, accent: cardAccent)
                                        .id("det-\(activity.id)")
                                }
                            }
                        }
                    }

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
                .padding(14)
            }
            .onChange(of: card.recentEvents.count) { _ in
                if isFollowingLive, let last = card.recentEvents.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("det-\(last.id)", anchor: .bottom)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

            if let detail = activity.detail, !detail.isEmpty {
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
}
