import SwiftUI

struct ClickableMessageContent: View {
    let content: String
    let context: ProjectContext?
    let onFileClicked: (String) -> Void
    var textAlignment: TextAlignment = .leading

    /// Rimuove marker CODERIDE (completi, incompleti, con spazi/newline). Durante lo streaming
    /// il modello emette token per token; possono comparire varianti come [ CODERIDE: o [CODERIDE\n:
    private var displayContent: String {
        var out = content
        guard let regex = try? NSRegularExpression(
            pattern: "\\[\\s*CODERIDE\\s*:[^\\]]*\\]?",
            options: .caseInsensitive
        ) else {
            return content
        }
        while true {
            let ns = out as NSString
            let fullRange = NSRange(location: 0, length: ns.length)
            guard let match = regex.firstMatch(in: out, range: fullRange) else { break }
            let start = out.index(out.startIndex, offsetBy: match.range.location)
            let end = out.index(start, offsetBy: match.range.length)
            out.removeSubrange(start..<end)
        }
        // Fallback: frammenti come [CODERIDE senza pipe (es. [CODERIDE:read incompleto)
        while let start = out.range(of: "[CODERIDE", options: .caseInsensitive) {
            if let end = out[start.upperBound...].firstIndex(of: "]") {
                out.removeSubrange(start.lowerBound..<out.index(after: end))
            } else {
                out.removeSubrange(start.lowerBound..<out.endIndex)
            }
        }
        return out
            .replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Text(buildAttributedString())
            .environment(\.openURL, OpenURLAction { url in
                if url.isFileURL { onFileClicked(url.path); return .handled }
                return .systemAction(url)
            })
            .font(.system(size: 14.5, weight: .regular, design: .default))
            .lineSpacing(6)
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
        let pattern = #"([a-zA-Z0-9_][a-zA-Z0-9_/.-]*\.(swift|ts|tsx|js|jsx|py|json|md|html|css|yaml|yml|xml|plist|strings)(?::\d+)?)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return result }
        let nsContent = displayContent as NSString
        let fullRange = NSRange(location: 0, length: nsContent.length)
        for match in regex.matches(in: displayContent, range: fullRange) {
            let fileRef = nsContent.substring(with: match.range)
            guard let strRange = Range(match.range, in: displayContent) else { continue }
            guard let lower = AttributedString.Index(strRange.lowerBound, within: result),
                  let upper = AttributedString.Index(strRange.upperBound, within: result) else {
                continue
            }
            result[lower..<upper].foregroundColor = NSColor.controlAccentColor
            result[lower..<upper].underlineStyle = .single
            result[lower..<upper].link = URL(fileURLWithPath: resolvePath(fileRef))
        }
        return result
    }

    private func applyMarkdownVisualStyling(to attributed: inout AttributedString) {
        for run in attributed.runs {
            let range = run.range
            guard let inlineIntent = run.inlinePresentationIntent else { continue }
            if inlineIntent.contains(.code) {
                attributed[range].font = .system(size: 13.5, weight: .regular, design: .monospaced)
                attributed[range].backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.65)
            }
        }
    }

    private func resolvePath(_ ref: String) -> String {
        let raw = ref.trimmingCharacters(in: .whitespaces)
        let t: String = {
            let parts = raw.split(separator: ":")
            if parts.count >= 2, Int(parts.last ?? "") != nil {
                return parts.dropLast().joined(separator: ":")
            }
            return raw
        }()
        if (t as NSString).isAbsolutePath { return t }
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
