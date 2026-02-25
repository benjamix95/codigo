import SwiftUI

// MARK: - Web Activity Live View (Search + Fetch, Cursor-style)

struct WebSearchLiveView: View {
    let activities: [TaskActivity]

    @State private var expandedIds: Set<UUID> = []
    @State private var hoveredId: UUID?

    private var webActivities: [TaskActivity] {
        activities.filter {
            $0.type == "web_search"
                || $0.type == "web_search_started"
                || $0.type == "web_search_completed"
                || $0.type == "web_search_failed"
                || $0.type == "web_fetch"
                || $0.type == "web_fetch_started"
                || $0.type == "web_fetch_completed"
                || $0.type == "web_fetch_failed"
        }
        .suffix(12)
        .map { $0 }
    }

    var body: some View {
        if !webActivities.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(spacing: 8) {
                    Image(systemName: "globe")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(WebSearchColors.accent)

                    Text("Web Activity")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(webActivities.count)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.quaternary)
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 8)

                Divider().opacity(0.3)

                // Activity rows
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(webActivities) { activity in
                        activityRow(activity)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
            .background(WebSearchColors.panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(WebSearchColors.panelBorder, lineWidth: 0.5)
            )
        }
    }

    // MARK: - Activity Row

    private func activityRow(_ activity: TaskActivity) -> some View {
        let isExpanded = expandedIds.contains(activity.id)
        let isHovered = hoveredId == activity.id
        let status = activityStatus(activity)
        let isFetch = activity.type.contains("web_fetch")
        let label = isFetch
            ? (activity.payload["url"] ?? activity.title)
            : (activity.payload["query"] ?? activity.title)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                // Status icon
                ZStack {
                    Circle()
                        .fill(status.color.opacity(0.12))
                        .frame(width: 22, height: 22)

                    Image(systemName: status.icon)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(status.color)
                }

                // Content
                VStack(alignment: .leading, spacing: 3) {
                    // Label text
                    Text(label)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(isExpanded ? nil : 1)

                    // Metadata row
                    HStack(spacing: 8) {
                        // Status label
                        Text(status.label)
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(status.color)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(status.color.opacity(0.08), in: Capsule())

                        // Result count (for search)
                        if !isFetch, let count = activity.payload["resultCount"], !count.isEmpty {
                            HStack(spacing: 3) {
                                Image(systemName: "doc.text")
                                    .font(.system(size: 8))
                                Text("\(count) results")
                                    .font(.system(size: 10))
                            }
                            .foregroundStyle(.tertiary)
                        }

                        // Content size (for fetch)
                        if isFetch, let detail = activity.detail, detail.contains("chars") {
                            HStack(spacing: 3) {
                                Image(systemName: "doc.plaintext")
                                    .font(.system(size: 8))
                                Text(detail)
                                    .font(.system(size: 10))
                            }
                            .foregroundStyle(.tertiary)
                        }

                        // Duration
                        if let duration = activity.payload["duration_ms"], !duration.isEmpty {
                            HStack(spacing: 3) {
                                Image(systemName: "clock")
                                    .font(.system(size: 8))
                                Text("\(duration)ms")
                                    .font(.system(size: 10, design: .monospaced))
                            }
                            .foregroundStyle(.quaternary)
                        }

                        Spacer()

                        // Expand/collapse
                        if hasExpandableContent(activity) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    if isExpanded {
                                        expandedIds.remove(activity.id)
                                    } else {
                                        expandedIds.insert(activity.id)
                                    }
                                }
                            } label: {
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.quaternary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)

            // Expanded content
            if isExpanded {
                expandedContent(activity)
                    .padding(.leading, 38)
                    .padding(.trailing, 8)
                    .padding(.bottom, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered ? WebSearchColors.rowHover : Color.clear)
        )
        .onHover { hovering in
            hoveredId = hovering ? activity.id : nil
        }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    // MARK: - Expanded Content

    @ViewBuilder
    private func expandedContent(_ activity: TaskActivity) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let detail = activity.detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .textSelection(.enabled)
            }

            if let output = activity.payload["output"], !output.isEmpty {
                ScrollView(.vertical, showsIndicators: true) {
                    Text(String(output.prefix(2000)))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 140)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(WebSearchColors.codeBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(WebSearchColors.codeBorder, lineWidth: 0.5)
                )
            }

            // URL if available
            if let url = activity.payload["url"], !url.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(.system(size: 9))
                        .foregroundStyle(WebSearchColors.accent)
                    Text(url)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(WebSearchColors.accent)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
            }

            // Error message if failed
            if activity.type == "web_search_failed" || activity.type == "web_fetch_failed" {
                if let error = activity.payload["error"] ?? activity.payload["stderr"] ?? activity.detail, !error.isEmpty {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(DesignSystem.Colors.error)
                        Text(error)
                            .font(.system(size: 10.5))
                            .foregroundStyle(DesignSystem.Colors.error.opacity(0.8))
                            .textSelection(.enabled)
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(DesignSystem.Colors.error.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(DesignSystem.Colors.error.opacity(0.12), lineWidth: 0.5)
                    )
                }
            }
        }
    }

    // MARK: - Helpers

    private func hasExpandableContent(_ activity: TaskActivity) -> Bool {
        !(activity.detail ?? "").isEmpty
            || !(activity.payload["output"] ?? "").isEmpty
            || !(activity.payload["url"] ?? "").isEmpty
            || activity.type == "web_search_failed"
            || activity.type == "web_fetch_failed"
    }

    private struct SearchStatus {
        let icon: String
        let label: String
        let color: Color
    }

    private func activityStatus(_ activity: TaskActivity) -> SearchStatus {
        switch activity.type {
        // Search statuses
        case "web_search_failed":
            return SearchStatus(icon: "xmark.circle.fill", label: "Failed", color: DesignSystem.Colors.error)
        case "web_search_completed":
            return SearchStatus(icon: "checkmark.circle.fill", label: "Done", color: .secondary)
        case "web_search_started":
            return SearchStatus(icon: "arrow.circlepath", label: "Searching", color: WebSearchColors.accent)
        // Fetch statuses
        case "web_fetch_failed":
            return SearchStatus(icon: "xmark.circle.fill", label: "Failed", color: DesignSystem.Colors.error)
        case "web_fetch_completed":
            return SearchStatus(icon: "checkmark.circle.fill", label: "Fetched", color: .secondary)
        case "web_fetch_started":
            return SearchStatus(icon: "arrow.down.circle", label: "Fetching", color: WebSearchColors.accent)
        case "web_fetch":
            return SearchStatus(icon: "globe", label: "Fetch", color: WebSearchColors.accent)
        default:
            return SearchStatus(icon: "magnifyingglass.circle.fill", label: "Search", color: WebSearchColors.accent)
        }
    }
}

// MARK: - Colors

private enum WebSearchColors {
    static let accent = Color.secondary
    static let panelBackground = Color(nsColor: .controlBackgroundColor).opacity(0.28)
    static let panelBorder = Color(nsColor: .separatorColor).opacity(0.35)
    static let rowHover = Color.primary.opacity(0.03)
    static let codeBackground = Color(nsColor: .controlBackgroundColor).opacity(0.32)
    static let codeBorder = Color(nsColor: .separatorColor).opacity(0.25)
}
