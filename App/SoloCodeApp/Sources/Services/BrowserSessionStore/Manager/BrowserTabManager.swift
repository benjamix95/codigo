import Foundation

@MainActor
public final class BrowserTabManager: ObservableObject {
    @Published public var tabs: [BrowserTab] = []
    @Published public var activeTabId: UUID?
    @Published public var showBookmarksPanel: Bool = false
    @Published public var showHistoryPanel: Bool = false

    @Published public var bookmarks: [BrowserBookmark] = [] {
        didSet { persistBookmarks() }
    }
    @Published public var history: [BrowserHistoryEntry] = [] {
        didSet { persistHistory() }
    }

    private let maxHistoryEntries = 500

    static let browserShouldOpenNotification = Notification.Name("soloCodeBrowserShouldOpen")

    public var activeTab: BrowserTab? {
        guard let id = activeTabId else { return tabs.first }
        return tabs.first { $0.id == id }
    }

    public var activeStore: BrowserSessionStore? {
        activeTab?.store
    }

    public init() {
        loadBookmarks()
        loadHistory()
        addNewTab()
    }

    // MARK: - Tab Management

    @discardableResult
    public func addNewTab(url: String? = nil) -> BrowserTab {
        let tab = BrowserTab(url: url)
        tabs.append(tab)
        activeTabId = tab.id
        return tab
    }

    public func closeTab(id: UUID) {
        guard tabs.count > 1 else { return }
        if let idx = tabs.firstIndex(where: { $0.id == id }) {
            let wasActive = activeTabId == id
            tabs.remove(at: idx)
            if wasActive {
                let newIdx = min(idx, tabs.count - 1)
                activeTabId = tabs[newIdx].id
            }
        }
    }

    public func selectTab(id: UUID) {
        activeTabId = id
    }

    // MARK: - Navigate (on active tab, opens browser)

    public func navigateActiveTab(to url: String) {
        if let tab = activeTab {
            tab.store.navigate(to: url)
        } else {
            addNewTab(url: url)
        }
        NotificationCenter.default.post(name: Self.browserShouldOpenNotification, object: nil)
    }

    // MARK: - Bookmarks

    public func addBookmark() {
        guard let store = activeStore, !store.currentURL.isEmpty else { return }
        let title = store.pageTitle.isEmpty ? store.currentURL : store.pageTitle
        if !bookmarks.contains(where: { $0.url == store.currentURL }) {
            bookmarks.append(BrowserBookmark(title: title, url: store.currentURL))
        }
    }

    public func removeBookmark(id: UUID) {
        bookmarks.removeAll { $0.id == id }
    }

    public func isBookmarked(_ url: String) -> Bool {
        bookmarks.contains { $0.url == url }
    }

    private func persistBookmarks() {
        if let data = try? JSONEncoder().encode(bookmarks) {
            UserDefaults.standard.set(data, forKey: "browser_bookmarks")
        }
    }

    private func loadBookmarks() {
        guard let data = UserDefaults.standard.data(forKey: "browser_bookmarks"),
              let saved = try? JSONDecoder().decode([BrowserBookmark].self, from: data) else { return }
        bookmarks = saved
    }

    // MARK: - History

    public func recordHistory(url: String, title: String) {
        let entry = BrowserHistoryEntry(title: title.isEmpty ? url : title, url: url)
        history.insert(entry, at: 0)
        if history.count > maxHistoryEntries {
            history = Array(history.prefix(maxHistoryEntries))
        }
    }

    public func clearHistory() {
        history.removeAll()
    }

    private func persistHistory() {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: "browser_history")
        }
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: "browser_history"),
              let saved = try? JSONDecoder().decode([BrowserHistoryEntry].self, from: data) else { return }
        history = saved
    }
}
