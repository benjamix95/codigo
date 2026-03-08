import SwiftUI

struct TaskActivityPanelView: View {
    @ObservedObject var store: TaskActivityStore

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(alignment: .leading, spacing: 3) {
                ForEach(store.activities.filter { TaskActivityStore.isConcreteVisibleEvent($0) }) {
                    activity in
                    TaskActivityRow(activity: activity)
                }
            }
            .padding(8)
        }
        .frame(maxHeight: 120)
        .background(DesignSystem.Colors.backgroundSecondary.opacity(0.5))
        .overlay(alignment: .bottom) {
            Rectangle().fill(DesignSystem.Colors.border).frame(height: 0.5)
        }
    }
}
