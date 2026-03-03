import CoderEngine
import SwiftUI

/// Inline activity timeline view displayed during assistant streaming.
/// Shows the list of operational steps (commands, file changes, web search, etc.)
/// invoked by the LLM via the stream. Each row is expandable to see details.
struct InlineActivityFeedView: View {
    let activities: [TaskActivity]
    let modeColor: Color
    let statusFromLLMOrActivity: String?
    let maxVisible: Int

    init(
        activities: [TaskActivity],
        modeColor: Color,
        statusFromLLMOrActivity: String? = nil,
        maxVisible: Int = 20
    ) {
        self.activities = activities
        self.modeColor = modeColor
        self.statusFromLLMOrActivity = statusFromLLMOrActivity
        self.maxVisible = maxVisible
    }

    @State private var expandedActivityIds: Set<UUID> = []

    private var visibleActivities: [TaskActivity] {
        activities
            .filter { TaskActivityStore.isConcreteVisibleEvent($0) }
            .suffix(maxVisible)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if visibleActivities.isEmpty {
                EmptyView()
            } else {
                ForEach(visibleActivities) { activity in
                    let isExpanded = expandedActivityIds.contains(activity.id)
                    activityRow(activity, isExpanded: isExpanded)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if isExpanded {
                                    expandedActivityIds.remove(activity.id)
                                } else {
                                    expandedActivityIds.insert(activity.id)
                                }
                            }
                        }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxWidth: 760, alignment: .leading)
    }
}
