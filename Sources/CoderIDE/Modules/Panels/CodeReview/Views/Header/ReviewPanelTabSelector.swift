import SwiftUI

/// Horizontal tab selector for the Code Review Panel.
struct ReviewPanelTabSelector: View {
    @ObservedObject var store: CodeReviewPanelStore

    var body: some View {
        HStack(spacing: 4) {
            ForEach(CodeReviewTab.allCases, id: \.self) { tab in
                Button {
                    store.selectTab(tab)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 8.5, weight: .semibold))
                        Text(tab.rawValue)
                            .font(.system(
                                size: 10,
                                weight: store.selectedTab == tab ? .semibold : .regular
                            ))
                    }
                    .foregroundStyle(
                        store.selectedTab == tab ? store.accent : .secondary
                    )
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(
                                store.selectedTab == tab
                                    ? store.accent.opacity(0.14) : .clear
                            )
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
