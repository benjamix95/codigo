import SwiftUI

struct ClickableMessageContent: View {
    let content: String
    let workspacePath: String
    let onFileClicked: (String) -> Void

    var body: some View {
        Text(buildAttributedString())
            .environment(\.openURL, OpenURLAction { url in
                if url.isFileURL {
                    onFileClicked(url.path)
                    return .handled
                }
                return .systemAction(url)
            })
            .font(.system(size: 13))
            .lineSpacing(3)
            .textSelection(.enabled)
    }

    private func buildAttributedString() -> AttributedString {
        var result = AttributedString()
        let pattern = #"([a-zA-Z0-9_][a-zA-Z0-9_/.-]*\.(swift|ts|tsx|js|jsx|py|json|md|html|css|yaml|yml|xml|plist|strings))\b"#

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return AttributedString(content)
        }

        let nsContent = content as NSString
        let fullRange = NSRange(location: 0, length: nsContent.length)
        var lastEnd = 0

        for match in regex.matches(in: content, range: fullRange) {
            if match.range.location > lastEnd {
                let plainRange = NSRange(location: lastEnd, length: match.range.location - lastEnd)
                result.append(AttributedString(nsContent.substring(with: plainRange)))
            }

            let fileRef = nsContent.substring(with: match.range)
            let resolvedPath = resolvePath(fileRef)
            var linkAttr = AttributedString(fileRef)
            linkAttr.foregroundColor = Color.accentColor
            linkAttr.underlineStyle = .single
            linkAttr.link = URL(fileURLWithPath: resolvedPath)
            result.append(linkAttr)

            lastEnd = match.range.location + match.range.length
        }

        if lastEnd < nsContent.length {
            let plainRange = NSRange(location: lastEnd, length: nsContent.length - lastEnd)
            result.append(AttributedString(nsContent.substring(with: plainRange)))
        }

        return result
    }

    private func resolvePath(_ fileRef: String) -> String {
        let trimmed = fileRef.trimmingCharacters(in: .whitespaces)
        if (trimmed as NSString).isAbsolutePath { return trimmed }
        if !workspacePath.isEmpty {
            return (workspacePath as NSString).appendingPathComponent(trimmed)
        }
        return trimmed
    }
}
