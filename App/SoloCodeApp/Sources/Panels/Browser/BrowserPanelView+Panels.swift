import SwiftUI
import AppKit

extension BrowserPanelView {
    // MARK: - Main Content

    var browserContent: some View {
        HStack(spacing: 0) {
            if tabManager.showBookmarksPanel {
                bookmarksPanel
                    .frame(width: 220)
                Divider().opacity(0.2)
            }
            if tabManager.showHistoryPanel {
                historyPanel
                    .frame(width: 220)
                Divider().opacity(0.2)
            }

            if let tab = tabManager.activeTab {
                VStack(spacing: 0) {
                    BrowserWebView(store: tab.store, tabManager: tabManager)
                        .id(tab.id)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if let img = tab.store.lastScreenshot, tab.store.lastScreenshotTimestamp != nil {
                        Divider().opacity(0.15)
                        screenshotPreview(img, store: tab.store)
                            .frame(height: 120)
                    }

                    if tab.store.showConsoleDrawer {
                        Divider().opacity(0.2)
                        consoleDrawer(store: tab.store)
                            .frame(height: max(100, CGFloat(consoleHeight)))
                    }
                }
            } else {
                Color.clear
            }
        }
    }

    // MARK: - Screenshot Preview

    private func screenshotPreview(_ image: NSImage, store: BrowserSessionStore) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(DesignSystem.Colors.borderSubtle, lineWidth: 0.5)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("Last Screenshot")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                if let ts = store.lastScreenshotTimestamp {
                    Text(ts, style: .time)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                }
            }

            Spacer()

            Button {
                store.lastScreenshot = nil
                store.lastScreenshotTimestamp = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(DesignSystem.Colors.backgroundPrimary)
    }

    // MARK: - Bookmarks Panel

    var bookmarksPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "star.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignSystem.Colors.warning)
                Text("Bookmarks")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                Spacer()
                Text("\(tabManager.bookmarks.count)")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            Divider().opacity(0.15)

            if tabManager.bookmarks.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "star")
                        .font(.system(size: 20))
                        .foregroundStyle(DesignSystem.Colors.textQuaternary)
                    Text("No bookmarks yet")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(tabManager.bookmarks) { bm in
                            bookmarkRow(bm)
                        }
                    }
                }
            }
        }
        .background(DesignSystem.Colors.backgroundPrimary)
    }

    private func bookmarkRow(_ bm: BrowserBookmark) -> some View {
        Button {
            activeStore?.navigate(to: bm.url)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "globe")
                    .font(.system(size: 9))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(bm.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .lineLimit(1)
                    Text(bm.url)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Open") { activeStore?.navigate(to: bm.url) }
            Button("Open in New Tab") { tabManager.addNewTab(url: bm.url) }
            Button("Copy URL") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(bm.url, forType: .string) }
            Divider()
            Button("Remove", role: .destructive) { tabManager.removeBookmark(id: bm.id) }
        }
    }

    // MARK: - History Panel

    var historyPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignSystem.Colors.browserColor)
                Text("History")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                Spacer()
                if !tabManager.history.isEmpty {
                    Button {
                        tabManager.clearHistory()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 9))
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear history")
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            Divider().opacity(0.15)

            if tabManager.history.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 20))
                        .foregroundStyle(DesignSystem.Colors.textQuaternary)
                    Text("No history")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(tabManager.history) { entry in
                            historyRow(entry)
                        }
                    }
                }
            }
        }
        .background(DesignSystem.Colors.backgroundPrimary)
    }

    private func historyRow(_ entry: BrowserHistoryEntry) -> some View {
        Button {
            activeStore?.navigate(to: entry.url)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "globe")
                    .font(.system(size: 9))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(entry.url)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                            .lineLimit(1)
                        Text(entry.timestamp, style: .time)
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(DesignSystem.Colors.textQuaternary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Open") { activeStore?.navigate(to: entry.url) }
            Button("Open in New Tab") { tabManager.addNewTab(url: entry.url) }
            Button("Copy URL") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(entry.url, forType: .string) }
            Button("Bookmark") { activeStore?.navigate(to: entry.url); tabManager.addBookmark() }
        }
    }
}
