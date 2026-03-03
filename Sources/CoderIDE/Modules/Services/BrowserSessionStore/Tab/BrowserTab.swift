import Foundation
import AppKit

@MainActor
public final class BrowserTab: ObservableObject, Identifiable {
    public let id = UUID()
    @Published public var store: BrowserSessionStore

    public var label: String {
        if !store.pageTitle.isEmpty { return store.pageTitle }
        if !store.currentURL.isEmpty {
            if let host = URL(string: store.currentURL)?.host { return host }
            return store.currentURL
        }
        return "New Tab"
    }

    public init(url: String? = nil) {
        self.store = BrowserSessionStore()
        if let url { store.navigate(to: url) }
    }
}
