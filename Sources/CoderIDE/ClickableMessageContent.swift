import SwiftUI

/// Parsa il contenuto del messaggio e rende i riferimenti a file cliccabili
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
        .font(DesignSystem.Typography.body)
        .foregroundStyle(DesignSystem.Colors.textPrimary)
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
            // Aggiungi testo prima del match
            if match.range.location > lastEnd {
                let plainRange = NSRange(location: lastEnd, length: match.range.location - lastEnd)
                let plainText = nsContent.substring(with: plainRange)
                result.append(AttributedString(plainText))
            }
            
            // Aggiungi il path file come link
            let fileRef = nsContent.substring(with: match.range)
            let resolvedPath = resolvePath(fileRef)
            var linkAttr = AttributedString(fileRef)
            linkAttr.foregroundColor = DesignSystem.Colors.primary
            linkAttr.underlineStyle = .single
            linkAttr.link = URL(fileURLWithPath: resolvedPath)
            result.append(linkAttr)
            
            lastEnd = match.range.location + match.range.length
        }
        
        // Aggiungi il resto
        if lastEnd < nsContent.length {
            let plainRange = NSRange(location: lastEnd, length: nsContent.length - lastEnd)
            let plainText = nsContent.substring(with: plainRange)
            result.append(AttributedString(plainText))
        }
        
        return result
    }
    
    private func resolvePath(_ fileRef: String) -> String {
        let trimmed = fileRef.trimmingCharacters(in: .whitespaces)
        if (trimmed as NSString).isAbsolutePath {
            return trimmed
        }
        if !workspacePath.isEmpty {
            return (workspacePath as NSString).appendingPathComponent(trimmed)
        }
        return trimmed
    }
}
