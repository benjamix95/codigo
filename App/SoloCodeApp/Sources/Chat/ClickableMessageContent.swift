import SwiftUI

struct ClickableMessageContent: View {
    let content: String
    let context: ProjectContext?
    let onFileClicked: (String) -> Void
    var textAlignment: TextAlignment = .leading
    @AppStorage("ui_sans_font_family") private var uiSansFontFamily = FontPreferences.defaultSansFamily
    @AppStorage("ui_sans_font_size") private var uiSansFontSize = FontPreferences.defaultSansSize
    @AppStorage("ui_code_font_family") private var uiCodeFontFamily = FontPreferences.defaultCodeFamily
    @AppStorage("ui_code_font_size") private var uiCodeFontSize = FontPreferences.defaultCodeSize

    /// Removes CODERIDE markers (complete, incomplete, with spaces/newlines). During streaming
    /// the model emits token by token; variants like [ CODERIDE: or [CODERIDE\n: may appear.
    private var displayContent: String {
        ChatStore.stripCoderideMarkers(content)
            .replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Text(buildAttributedString())
            .environment(\.openURL, OpenURLAction { url in
                MessageLinkRouter.open(url, onFileClicked: onFileClicked)
            })
            .font(FontPreferences.resolveSansFont(
                size: FontPreferences.sanitizeSize(uiSansFontSize + 2.5, kind: .sans),
                family: uiSansFontFamily
            ))
            .lineSpacing(7)
            .multilineTextAlignment(textAlignment)
            .textSelection(.enabled)
            .padding(.vertical, 1)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func buildAttributedString() -> AttributedString {
        var result: AttributedString
        if let markdown = try? AttributedString(
            markdown: displayContent,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .full,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        ) {
            result = markdown
        } else {
            result = AttributedString(displayContent)
        }
        applyMarkdownVisualStyling(to: &result)
        MarkdownContentView.applyFileReferenceLinks(
            in: &result,
            color: NSColor.controlAccentColor,
            resolver: { resolvePath($0) }
        )
        return result
    }

    private func applyMarkdownVisualStyling(to attributed: inout AttributedString) {
        for run in attributed.runs {
            let range = run.range
            guard let inlineIntent = run.inlinePresentationIntent else { continue }
            if inlineIntent.contains(.code) {
                attributed[range].font = FontPreferences.resolveCodeFont(
                    size: FontPreferences.sanitizeSize(uiCodeFontSize + 1.5, kind: .code),
                    family: uiCodeFontFamily
                )
                attributed[range].backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.65)
            }
        }
    }

    private func resolvePath(_ ref: String) -> String {
        let raw = ref.trimmingCharacters(in: .whitespaces)
        let t = raw.replacingOccurrences(
            of: #":\d+(?::\d+)?$"#,
            with: "",
            options: .regularExpression
        )
        let parts = t.split(separator: "/", omittingEmptySubsequences: false)
        if parts.contains("..") { return t }
        if let context {
            switch ContextPathResolver.resolve(reference: t, context: context) {
            case .resolved(let path):
                return path
            case .ambiguous(let matches):
                return matches.first ?? t
            case .notFound:
                break
            }
        }
        return t
    }
}
