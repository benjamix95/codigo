import Foundation

// MARK: - HTML to Markdown Converter

/// Lightweight, zero-dependency HTML → Markdown converter.
/// Uses regex-based transformations for speed and simplicity.
public enum HTMLToMarkdown {

    /// Convert HTML string to clean Markdown.
    public static func convert(_ html: String) -> String {
        var text = html

        // 1. Remove entire blocks of non-content tags
        let blockTags = ["script", "style", "noscript", "svg", "iframe", "object", "embed", "applet", "form"]
        for tag in blockTags {
            text = replaceRegex(
                in: text,
                pattern: "<\(tag)[^>]*>[\\s\\S]*?</\(tag)>",
                with: ""
            )
        }

        // 2. Try to extract <article> or <main> content for readability
        text = extractMainContent(text)

        // 3. Remove <nav>, <footer>, <header>, <aside> blocks (after content extraction)
        let removeTags = ["nav", "footer", "aside"]
        for tag in removeTags {
            text = replaceRegex(in: text, pattern: "<\(tag)[^>]*>[\\s\\S]*?</\(tag)>", with: "")
        }

        // 4. Convert headings: <h1>...</h1> → # ...
        for level in 1...6 {
            let prefix = String(repeating: "#", count: level)
            text = replaceRegex(
                in: text,
                pattern: "<h\(level)[^>]*>(.*?)</h\(level)>",
                with: "\n\n\(prefix) $1\n\n"
            )
        }

        // 5. Convert links: <a href="url">text</a> → [text](url)
        text = replaceRegex(
            in: text,
            pattern: #"<a[^>]*href="([^"]*)"[^>]*>([\s\S]*?)</a>"#,
            with: "[$2]($1)"
        )

        // 6. Convert emphasis
        text = replaceRegex(in: text, pattern: "<strong[^>]*>(.*?)</strong>", with: "**$1**")
        text = replaceRegex(in: text, pattern: "<b[^>]*>(.*?)</b>", with: "**$1**")
        text = replaceRegex(in: text, pattern: "<em[^>]*>(.*?)</em>", with: "*$1*")
        text = replaceRegex(in: text, pattern: "<i[^>]*>(.*?)</i>", with: "*$1*")

        // 7. Convert code
        text = replaceRegex(in: text, pattern: "<code[^>]*>(.*?)</code>", with: "`$1`")
        text = replaceRegex(
            in: text,
            pattern: "<pre[^>]*>(.*?)</pre>",
            with: "\n```\n$1\n```\n"
        )

        // 8. Convert lists
        text = replaceRegex(in: text, pattern: "<li[^>]*>(.*?)</li>", with: "\n- $1")
        text = replaceRegex(in: text, pattern: "</?[uo]l[^>]*>", with: "\n")

        // 9. Convert paragraphs and line breaks
        text = replaceRegex(in: text, pattern: "<br[^>]*/?>", with: "\n")
        text = replaceRegex(in: text, pattern: "<p[^>]*>", with: "\n\n")
        text = replaceRegex(in: text, pattern: "</p>", with: "\n\n")
        text = replaceRegex(in: text, pattern: "<div[^>]*>", with: "\n")
        text = replaceRegex(in: text, pattern: "</div>", with: "\n")

        // 10. Convert <hr> → ---
        text = replaceRegex(in: text, pattern: "<hr[^>]*/?>", with: "\n\n---\n\n")

        // 11. Convert blockquotes
        text = replaceRegex(in: text, pattern: "<blockquote[^>]*>(.*?)</blockquote>", with: "\n> $1\n")

        // 12. Convert tables (basic)
        text = replaceRegex(in: text, pattern: "<tr[^>]*>", with: "\n| ")
        text = replaceRegex(in: text, pattern: "</tr>", with: " |")
        text = replaceRegex(in: text, pattern: "<t[hd][^>]*>(.*?)</t[hd]>", with: "$1 | ")

        // 13. Strip all remaining HTML tags
        text = replaceRegex(in: text, pattern: "<[^>]+>", with: "")

        // 14. Decode HTML entities
        text = decodeHTMLEntities(text)

        // 15. Collapse excessive whitespace
        text = replaceRegex(in: text, pattern: "[ \\t]+", with: " ")
        text = replaceRegex(in: text, pattern: "\\n[ \\t]+", with: "\n")
        text = replaceRegex(in: text, pattern: "\\n{3,}", with: "\n\n")

        // 16. Final trim
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        return text
    }

    /// Strip HTML tags from a string (used for cleaning search result titles/snippets).
    public static func stripTags(_ html: String) -> String {
        var text = replaceRegex(in: html, pattern: "<[^>]+>", with: "")
        text = decodeHTMLEntities(text)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Private Helpers

    /// Try to extract <article> or <main> content for better readability.
    /// Falls back to <body> if neither is found.
    private static func extractMainContent(_ html: String) -> String {
        // Try <article> first
        if let content = extractTag("article", from: html) {
            return content
        }
        // Try <main>
        if let content = extractTag("main", from: html) {
            return content
        }
        // Try <body>
        if let content = extractTag("body", from: html) {
            return content
        }
        return html
    }

    private static func extractTag(_ tag: String, from html: String) -> String? {
        let pattern = "<\(tag)[^>]*>([\\s\\S]*?)</\(tag)>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let nsHTML = html as NSString
        guard let match = regex.firstMatch(in: html, options: [], range: NSRange(location: 0, length: nsHTML.length)),
              match.numberOfRanges > 1 else { return nil }
        let range = match.range(at: 1)
        guard range.location != NSNotFound else { return nil }
        return nsHTML.substring(with: range)
    }

    private static func replaceRegex(in text: String, pattern: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return text
        }
        return regex.stringByReplacingMatches(
            in: text,
            options: [],
            range: NSRange(location: 0, length: (text as NSString).length),
            withTemplate: replacement
        )
    }

    private static func decodeHTMLEntities(_ text: String) -> String {
        var result = text
        let entities: [(String, String)] = [
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&#39;", "'"),
            ("&apos;", "'"),
            ("&nbsp;", " "),
            ("&mdash;", "—"),
            ("&ndash;", "–"),
            ("&laquo;", "«"),
            ("&raquo;", "»"),
            ("&bull;", "•"),
            ("&hellip;", "…"),
            ("&copy;", "©"),
            ("&reg;", "®"),
            ("&trade;", "™"),
            ("&times;", "×"),
            ("&divide;", "÷"),
        ]
        for (entity, char) in entities {
            result = result.replacingOccurrences(of: entity, with: char)
        }
        // Numeric entities: \\\&#123; → character
        if let numericRegex = try? NSRegularExpression(pattern: "&#(\\d+);") {
            let nsResult = result as NSString
            let matches = numericRegex.matches(in: result, options: [], range: NSRange(location: 0, length: nsResult.length))
            for match in matches.reversed() {
                if match.numberOfRanges > 1 {
                    let codeRange = match.range(at: 1)
                    if codeRange.location != NSNotFound,
                       let code = Int(nsResult.substring(with: codeRange)),
                       let scalar = Unicode.Scalar(code) {
                        result = (result as NSString).replacingCharacters(in: match.range, with: String(scalar))
                    }
                }
            }
        }
        // Hex numeric entities: &#x1F4A9; → character
        if let hexRegex = try? NSRegularExpression(pattern: "&#x([0-9a-fA-F]+);") {
            let nsResult = result as NSString
            let matches = hexRegex.matches(in: result, options: [], range: NSRange(location: 0, length: nsResult.length))
            for match in matches.reversed() {
                if match.numberOfRanges > 1 {
                    let hexRange = match.range(at: 1)
                    if hexRange.location != NSNotFound,
                       let code = UInt32(nsResult.substring(with: hexRange), radix: 16),
                       let scalar = Unicode.Scalar(code) {
                        result = (result as NSString).replacingCharacters(in: match.range, with: String(scalar))
                    }
                }
            }
        }
        return result
    }
}
