import SwiftUI
import AppKit

extension BrowserPanelView {
    // MARK: - Tab Bar

    var browserTabBar: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(tabManager.tabs) { tab in
                        browserTabItem(tab)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            Divider().opacity(0.2).frame(height: 26)

            Button {
                withAnimation(.snappy(duration: 0.15)) {
                    _ = tabManager.addNewTab()
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New tab")
        }
        .frame(height: 28)
        .background { DesignSystem.Colors.backgroundPrimary.opacity(0.7) }
    }

    private func browserTabItem(_ tab: BrowserTab) -> some View {
        let isActive = tabManager.activeTabId == tab.id
        return HStack(spacing: 4) {
            if tab.store.isLoading {
                ProgressView().controlSize(.mini).scaleEffect(0.5)
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 8))
                    .foregroundStyle(isActive ? DesignSystem.Colors.browserColor : DesignSystem.Colors.textTertiary)
            }

            Text(tab.label)
                .font(.system(size: 10.5, weight: isActive ? .medium : .regular))
                .foregroundStyle(isActive ? DesignSystem.Colors.textPrimary : DesignSystem.Colors.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: 120)

            if tabManager.tabs.count > 1 {
                Button {
                    withAnimation(.snappy(duration: 0.15)) {
                        tabManager.closeTab(id: tab.id)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(isActive ? 1 : 0.5)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isActive ? DesignSystem.Colors.backgroundSecondary : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            tabManager.selectTab(id: tab.id)
        }
        .contextMenu {
            Button("Close Tab") { tabManager.closeTab(id: tab.id) }
                .disabled(tabManager.tabs.count <= 1)
            Button("Duplicate Tab") {
                tabManager.addNewTab(url: tab.store.currentURL.isEmpty ? nil : tab.store.currentURL)
            }
            Divider()
            Button("Close Other Tabs", role: .destructive) {
                let others = tabManager.tabs.filter { $0.id != tab.id }.map(\.id)
                for otherId in others { tabManager.closeTab(id: otherId) }
            }
            .disabled(tabManager.tabs.count <= 1)
        }
    }
}
