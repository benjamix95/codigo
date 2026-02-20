import SwiftUI

struct ClickableMessageContent: View {
    let content: String
    let context: ProjectContext?
    let onFileClicked: (String) -> Void
    var textAlignment: TextAlignment = .leading

    /// Rimuove marker CODERIDE (completi e incompleti). Durante lo streaming il modello
    /// emette token per token, quindi `[CODERIDE:read|path=x` senza `]` resta visibile
    /// se non gestiamo il caso incompleto.
    private var displayContent: String {
        var out = content
        while let start = out.range(of: "[CODERIDE:", options: .caseInsensitive) {
            if let end = out[start.upperBound...].firstIndex(of: "]") {
                out.removeSubrange(start.lowerBound..<out.index(after: end))
            } else {
                // marker incompleto (streaming): rimuovi da [CODERIDE: fino a fine stringa
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
            .font(.system(size: 13))
            .lineSpacing(3)
            .multilineTextAlignment(textAlignment)
            .textSelection(.enabled)
    }

    private func buildAttributedString() -> AttributedString {
        var result = AttributedString()
        let pattern = #"([a-zA-Z0-9_][a-zA-Z0-9_/.-]*\.(swift|ts|tsx|js|jsx|py|json|md|html|css|yaml|yml|xml|plist|strings)(?::\d+)?)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return AttributedString(displayContent) }
        let nsContent = displayContent as NSString
        let fullRange = NSRange(location: 0, length: nsContent.length)
        var lastEnd = 0
        for match in regex.matches(in: displayContent, range: fullRange) {
            if match.range.location > lastEnd {
                result.append(AttributedString(nsContent.substring(with: NSRange(location: lastEnd, length: match.range.location - lastEnd))))
            }
            let fileRef = nsContent.substring(with: match.range)
            var linkAttr = AttributedString(fileRef)
            linkAttr.foregroundColor = NSColor.controlAccentColor
            linkAttr.underlineStyle = .single
            linkAttr.link = URL(fileURLWithPath: resolvePath(fileRef))
            result.append(linkAttr)
            lastEnd = match.range.location + match.range.length
        }
        if lastEnd < nsContent.length {
            result.append(AttributedString(nsContent.substring(with: NSRange(location: lastEnd, length: nsContent.length - lastEnd))))
        }
        return result
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
