import Foundation
import SwiftUI

private enum MarkdownDisplayContentCache {
    static let cache: NSCache<NSString, NSString> = {
        let c = NSCache<NSString, NSString>()
        c.countLimit = 512
        c.totalCostLimit = 16 * 1024 * 1024
        return c
    }()

    static func key(content: String, isStreaming: Bool, aggressive: Bool, normalizeLayout: Bool) -> NSString {
        var hasher = Hasher()
        hasher.combine(content)
        hasher.combine(isStreaming)
        hasher.combine(aggressive)
        hasher.combine(normalizeLayout)
        let digest = hasher.finalize()
        return
            "\(isStreaming ? 1 : 0)|\(aggressive ? 1 : 0)|\(normalizeLayout ? 1 : 0)|\(content.count)|\(digest)"
            as NSString
    }
}

struct MarkdownContentView: View {
    let content: String
    let context: ProjectContext?
    let onFileClicked: (String) -> Void
    var textAlignment: TextAlignment = .leading
    var isStreaming: Bool = false
    var aggressiveSanitization: Bool? = nil
    var fillWidth: Bool = true
    var normalizeDisplayLayout: Bool = true

    var shouldUseAggressiveSanitization: Bool {
        aggressiveSanitization ?? true
    }

    var displayContent: String {
        let key = MarkdownDisplayContentCache.key(
            content: content,
            isStreaming: isStreaming,
            aggressive: shouldUseAggressiveSanitization,
            normalizeLayout: normalizeDisplayLayout
        )
        if let cached = MarkdownDisplayContentCache.cache.object(forKey: key) {
            return cached as String
        }

        let stripped = ChatStore.stripCoderideMarkers(content, aggressive: shouldUseAggressiveSanitization)
        let computed: String
        if isStreaming {
            computed = stripped.replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: .regularExpression)
        } else if normalizeDisplayLayout {
            computed = Self.normalizeAssistantDisplayLayout(stripped)
                .replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: .regularExpression)
        } else {
            computed = stripped.replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: .regularExpression)
        }
        MarkdownDisplayContentCache.cache.setObject(
            computed as NSString,
            forKey: key,
            cost: min(32_768, computed.utf16.count)
        )
        return computed
    }

    @Environment(\.colorScheme) var colorScheme
    @AppStorage("ui_sans_font_family") var uiSansFontFamily = FontPreferences.defaultSansFamily
    @AppStorage("ui_sans_font_size") var uiSansFontSize = FontPreferences.defaultSansSize
    @AppStorage("ui_code_font_family") var uiCodeFontFamily = FontPreferences.defaultCodeFamily
    @AppStorage("ui_code_font_size") var uiCodeFontSize = FontPreferences.defaultCodeSize
    @State var cachedBlocks: [MarkdownBlock]?

    // MARK: - Body

    var body: some View {
        contentBody
    }
}
