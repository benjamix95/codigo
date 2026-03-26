import Foundation
import SwiftUI

// MARK: - MarkdownSettings Environment

/// Aggregates font preferences for markdown rendering.
/// Injected once at the chat panel root via `MarkdownSettingsProvider`,
/// replacing 4 separate `@AppStorage` reads per MarkdownContentView instance.
struct MarkdownSettings: Equatable {
    var sansFontFamily: String = FontPreferences.defaultSansFamily
    var sansFontSize: Double = FontPreferences.defaultSansSize
    var codeFontFamily: String = FontPreferences.defaultCodeFamily
    var codeFontSize: Double = FontPreferences.defaultCodeSize
}

private struct MarkdownSettingsKey: EnvironmentKey {
    static let defaultValue = MarkdownSettings()
}

extension EnvironmentValues {
    var markdownSettings: MarkdownSettings {
        get { self[MarkdownSettingsKey.self] }
        set { self[MarkdownSettingsKey.self] = newValue }
    }
}

/// Reads @AppStorage values once and injects as MarkdownSettings environment.
struct MarkdownSettingsProvider: ViewModifier {
    @AppStorage("ui_sans_font_family") private var sansFontFamily = FontPreferences.defaultSansFamily
    @AppStorage("ui_sans_font_size") private var sansFontSize = FontPreferences.defaultSansSize
    @AppStorage("ui_code_font_family") private var codeFontFamily = FontPreferences.defaultCodeFamily
    @AppStorage("ui_code_font_size") private var codeFontSize = FontPreferences.defaultCodeSize

    func body(content: Content) -> some View {
        content.environment(\.markdownSettings, MarkdownSettings(
            sansFontFamily: sansFontFamily,
            sansFontSize: sansFontSize,
            codeFontFamily: codeFontFamily,
            codeFontSize: codeFontSize
        ))
    }
}

private enum MarkdownDisplayContentCache {
    private final class SendableCache: @unchecked Sendable {
        let underlying: NSCache<NSString, NSString> = {
            let c = NSCache<NSString, NSString>()
            c.countLimit = 512
            c.totalCostLimit = 16 * 1024 * 1024
            return c
        }()
    }
    private static let holder = SendableCache()
    static var cache: NSCache<NSString, NSString> { holder.underlying }

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
    @Environment(\.markdownSettings) var markdownSettings
    @State var cachedBlocks: [MarkdownBlock]?

    // MARK: - Backward-compatible accessors
    // These forward to markdownSettings so extension files can keep
    // using the short names without changes to every call site.
    var uiSansFontFamily: String { markdownSettings.sansFontFamily }
    var uiSansFontSize: Double { markdownSettings.sansFontSize }
    var uiCodeFontFamily: String { markdownSettings.codeFontFamily }
    var uiCodeFontSize: Double { markdownSettings.codeFontSize }

    // MARK: - Body

    var body: some View {
        contentBody
    }
}
