import SwiftUI

extension WebSearchLiveView {
    func hasExpandableContent(_ activity: TaskActivity) -> Bool {
        !(activity.detail ?? "").isEmpty
            || !(activity.payload["output"] ?? "").isEmpty
            || !(activity.payload["url"] ?? "").isEmpty
            || activity.type == "web_search_failed"
            || activity.type == "web_fetch_failed"
    }

    struct SearchStatus {
        let icon: String
        let label: String
        let color: Color
    }

    func activityStatus(_ activity: TaskActivity) -> SearchStatus {
        switch activity.type {
        case "web_search_failed":
            return SearchStatus(icon: "xmark.circle.fill", label: "Failed", color: DesignSystem.Colors.error)
        case "web_search_completed":
            return SearchStatus(icon: "checkmark.circle.fill", label: "Done", color: .secondary)
        case "web_search_started":
            return SearchStatus(icon: "arrow.circlepath", label: "Searching", color: WebSearchColors.accent)
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

enum WebSearchColors {
    static let accent = Color.secondary
    static let panelBackground = Color(nsColor: .controlBackgroundColor).opacity(0.28)
    static let panelBorder = Color(nsColor: .separatorColor).opacity(0.35)
    static let rowHover = Color.primary.opacity(0.03)
    static let codeBackground = Color(nsColor: .controlBackgroundColor).opacity(0.32)
    static let codeBorder = Color(nsColor: .separatorColor).opacity(0.25)
}
