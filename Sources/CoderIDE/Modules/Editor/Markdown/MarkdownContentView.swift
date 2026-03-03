import SwiftUI

struct MarkdownContentView: View {
    let content: String
    let context: ProjectContext?
    let onFileClicked: (String) -> Void
    var textAlignment: TextAlignment = .leading
    var isStreaming: Bool = false
    var aggressiveSanitization: Bool? = nil
    var fillWidth: Bool = true

    var shouldUseAggressiveSanitization: Bool {
        aggressiveSanitization ?? true
    }

    var displayContent: String {
        let stripped = ChatStore.stripCoderideMarkers(content, aggressive: shouldUseAggressiveSanitization)
        if isStreaming {
            return stripped.replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: .regularExpression)
        }
        return Self.normalizeAssistantDisplayLayout(stripped)
            .replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: .regularExpression)
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
