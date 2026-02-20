import AppKit
import SwiftUI

// MARK: - Parsed Block Types

private enum MarkdownBlock: Identifiable {
    case text(String)
    case codeBlock(language: String?, code: String)
    case thinking(content: String)
    case heading(level: Int, text: String)
    case horizontalRule
    case blockquote(String)

    var id: String {
        switch self {
        case .text(let t): return "txt-\(t.hashValue)"
        case .codeBlock(let l, let c): return "code-\(l ?? "")-\(c.hashValue)"
        case .thinking(let t): return "think-\(t.hashValue)"
        case .heading(let lvl, let t): return "h\(lvl)-\(t.hashValue)"
        case .horizontalRule: return "hr-\(UUID().uuidString)"
        case .blockquote(let t): return "bq-\(t.hashValue)"
        }
    }
}

// MARK: - Main View

struct ClickableMessageContent: View {
    let content: String
    let context: ProjectContext?
    let onFileClicked: (String) -> Void

    @State private var collapsedThinking: Set<String> = []
    @State private var hoveredCodeBlock: String?
    @State private var copiedId: String?

    private var blocks: [MarkdownBlock] {
        MarkdownBlockParser.parse(content)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                renderBlock(block, index: index)
            }
        }
        .environment(
            \.openURL,
            OpenURLAction { url in
                if url.isFileURL {
                    onFileClicked(url.path)
                    return .handled
                }
                return .systemAction(url)
            })
    }

    // MARK: - Block Renderer

    @ViewBuilder
    private func renderBlock(_ block: MarkdownBlock, index: Int) -> some View {
        switch block {
        case .text(let text):
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                richText(text)
                    .padding(.vertical, 3)
            }

        case .codeBlock(let language, let code):
            codeBlockView(language: language, code: code, blockId: block.id)
                .padding(.vertical, 6)

        case .thinking(let content):
            thinkingBlockView(content: content, blockId: block.id)
                .padding(.vertical, 6)

        case .heading(let level, let text):
            headingView(level: level, text: text)
                .padding(.top, index == 0 ? 0 : 10)
                .padding(.bottom, 4)

        case .horizontalRule:
            Divider()
                .padding(.vertical, 8)

        case .blockquote(let text):
            blockquoteView(text: text)
                .padding(.vertical, 4)
        }
    }

    // MARK: - Rich Inline Text

    private func richText(_ text: String) -> some View {
        Text(buildAttributedString(from: text))
            .font(.system(size: 13, weight: .regular))
            .lineSpacing(4)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func buildAttributedString(from text: String) -> AttributedString {
        var result = AttributedString()
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        for (lineIndex, line) in lines.enumerated() {
            if lineIndex > 0 {
                result.append(AttributedString("\n"))
            }

            // Process bullet points
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let isBullet =
                trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("• ")
            let isNumbered = isNumberedListItem(trimmed)

            if isBullet {
                let indent = String(
                    repeating: " ",
                    count: max(0, line.count - line.drop(while: { $0 == " " }).count))
                var bulletAttr = AttributedString(indent + "  •  ")
                bulletAttr.foregroundColor = NSColor.tertiaryLabelColor
                result.append(bulletAttr)
                let content = String(trimmed.dropFirst(2))
                result.append(parseInlineFormatting(content))
            } else if isNumbered {
                let parts = trimmed.split(separator: ".", maxSplits: 1)
                if parts.count == 2 {
                    let indent = String(
                        repeating: " ",
                        count: max(0, line.count - line.drop(while: { $0 == " " }).count))
                    var numAttr = AttributedString(indent + "  \(parts[0]).  ")
                    numAttr.foregroundColor = NSColor.secondaryLabelColor
                    numAttr.font = .monospacedDigit(.system(size: 13, weight: .medium))()
                    result.append(numAttr)
                    let content = parts[1].trimmingCharacters(in: .whitespaces)
                    result.append(parseInlineFormatting(content))
                } else {
                    result.append(parseInlineFormatting(line))
                }
            } else {
                result.append(parseInlineFormatting(line))
            }
        }

        return result
    }

    private func isNumberedListItem(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let dotIndex = trimmed.firstIndex(of: ".") else { return false }
        let prefix = trimmed[trimmed.startIndex..<dotIndex]
        return !prefix.isEmpty && prefix.allSatisfy(\.isNumber) && dotIndex < trimmed.endIndex
    }

    private func parseInlineFormatting(_ text: String) -> AttributedString {
        var result = AttributedString()
        let scanner = InlineScanner(text)
        let segments = scanner.scan()

        for segment in segments {
            switch segment {
            case .plain(let str):
                result.append(resolveFileLinks(in: str))

            case .bold(let str):
                var attr = resolveFileLinks(in: str)
                attr.font = .system(size: 13, weight: .semibold)
                result.append(attr)

            case .italic(let str):
                var attr = resolveFileLinks(in: str)
                attr.font = .system(size: 13).italic()
                result.append(attr)

            case .boldItalic(let str):
                var attr = resolveFileLinks(in: str)
                attr.font = .system(size: 13, weight: .semibold).italic()
                result.append(attr)

            case .inlineCode(let str):
                var attr = AttributedString(" \(str) ")
                attr.font = .system(size: 12, design: .monospaced)
                attr.foregroundColor = NSColor(Color.accentColor.opacity(0.85))
                attr.backgroundColor = NSColor(Color.accentColor.opacity(0.08))
                result.append(attr)

            case .link(let title, let urlString):
                var attr = AttributedString(title)
                attr.foregroundColor = NSColor.controlAccentColor
                attr.underlineStyle = .single
                if let url = URL(string: urlString) {
                    attr.link = url
                }
                result.append(attr)

            case .strikethrough(let str):
                var attr = resolveFileLinks(in: str)
                attr.strikethroughStyle = .single
                result.append(attr)
            }
        }

        return result
    }

    // MARK: - File Path Links

    private func resolveFileLinks(in text: String) -> AttributedString {
        var result = AttributedString()
        let pattern =
            #"([a-zA-Z0-9_][a-zA-Z0-9_/.\-]*\.(swift|ts|tsx|js|jsx|py|rs|go|rb|java|kt|c|cpp|h|hpp|json|md|html|css|scss|yaml|yml|xml|toml|plist|strings|sh|bash|zsh|Dockerfile|Makefile)(?::\d+(?:-\d+)?)?)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return AttributedString(text)
        }

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        var lastEnd = 0

        for match in regex.matches(in: text, range: fullRange) {
            if match.range.location > lastEnd {
                let plain = nsText.substring(
                    with: NSRange(location: lastEnd, length: match.range.location - lastEnd))
                result.append(AttributedString(plain))
            }
            let fileRef = nsText.substring(with: match.range)
            var linkAttr = AttributedString(fileRef)
            linkAttr.foregroundColor = NSColor.controlAccentColor
            linkAttr.underlineStyle = .single
            linkAttr.font = .system(size: 12.5, weight: .medium, design: .monospaced)
            linkAttr.link = URL(fileURLWithPath: resolvePath(fileRef))
            result.append(linkAttr)
            lastEnd = match.range.location + match.range.length
        }

        if lastEnd < nsText.length {
            let remaining = nsText.substring(
                with: NSRange(location: lastEnd, length: nsText.length - lastEnd))
            result.append(AttributedString(remaining))
        }

        return result
    }

    private func resolvePath(_ ref: String) -> String {
        let raw = ref.trimmingCharacters(in: .whitespaces)
        let pathOnly: String = {
            let parts = raw.split(separator: ":")
            if parts.count >= 2, Int(parts.last ?? "") != nil {
                return parts.dropLast().joined(separator: ":")
            }
            return raw
        }()

        if (pathOnly as NSString).isAbsolutePath { return pathOnly }

        if let context {
            switch ContextPathResolver.resolve(reference: pathOnly, context: context) {
            case .resolved(let path): return path
            case .ambiguous(let matches): return matches.first ?? pathOnly
            case .notFound: break
            }
        }
        return pathOnly
    }

    // MARK: - Code Block

    private func codeBlockView(language: String?, code: String, blockId: String) -> some View {
        let isHovered = hoveredCodeBlock == blockId
        let isCopied = copiedId == blockId
        let lineCount = code.components(separatedBy: "\n").count

        return VStack(alignment: .leading, spacing: 0) {
            // Header bar
            HStack(spacing: 8) {
                if let lang = language, !lang.isEmpty {
                    Text(lang.lowercased())
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                }

                Spacer()

                Text("\(lineCount) lines")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.quaternary)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    copiedId = blockId
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        if copiedId == blockId { copiedId = nil }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10, weight: .medium))
                        Text(isCopied ? "Copied" : "Copy")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(isCopied ? Color.green : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.05), in: Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.03))

            Divider().opacity(0.3)

            // Code content with line numbers
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 0) {
                    // Line numbers
                    VStack(alignment: .trailing, spacing: 0) {
                        ForEach(1...max(1, lineCount), id: \.self) { num in
                            Text("\(num)")
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(Color.primary.opacity(0.18))
                                .frame(height: 19)
                        }
                    }
                    .padding(.leading, 12)
                    .padding(.trailing, 8)
                    .padding(.vertical, 10)

                    Divider()
                        .opacity(0.2)
                        .padding(.vertical, 6)

                    // Code
                    Text(buildCodeAttributedString(code, language: language))
                        .font(.system(size: 12, design: .monospaced))
                        .lineSpacing(2.5)
                        .textSelection(.enabled)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .background(CodeBlockColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isHovered ? Color.accentColor.opacity(0.2) : CodeBlockColors.border,
                    lineWidth: 0.5
                )
        )
        .onHover { hovering in
            hoveredCodeBlock = hovering ? blockId : nil
        }
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }

    private func buildCodeAttributedString(_ code: String, language: String?) -> AttributedString {
        var result = AttributedString()
        let lines = code.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

        for (lineIndex, line) in lines.enumerated() {
            if lineIndex > 0 {
                result.append(AttributedString("\n"))
            }
            result.append(syntaxHighlight(line, language: language))
        }
        return result
    }

    // MARK: - Syntax Highlighting (lightweight)

    private func syntaxHighlight(_ line: String, language: String?) -> AttributedString {
        var result = AttributedString()
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)

        // Diff lines
        if trimmedLine.hasPrefix("+") && !trimmedLine.hasPrefix("+++") {
            var attr = AttributedString(line)
            attr.foregroundColor = NSColor(SyntaxColors.added)
            attr.backgroundColor = NSColor(SyntaxColors.addedBg)
            return attr
        }
        if trimmedLine.hasPrefix("-") && !trimmedLine.hasPrefix("---") {
            var attr = AttributedString(line)
            attr.foregroundColor = NSColor(SyntaxColors.removed)
            attr.backgroundColor = NSColor(SyntaxColors.removedBg)
            return attr
        }

        // Comment lines
        if trimmedLine.hasPrefix("//") || trimmedLine.hasPrefix("#") || trimmedLine.hasPrefix("--")
        {
            var attr = AttributedString(line)
            attr.foregroundColor = NSColor(SyntaxColors.comment)
            return attr
        }

        // Generic keyword + string highlighting
        let segments = tokenizeLine(line, language: language)
        for seg in segments {
            var attr = AttributedString(seg.text)
            switch seg.kind {
            case .keyword:
                attr.foregroundColor = NSColor(SyntaxColors.keyword)
                attr.font = .system(size: 12, weight: .medium, design: .monospaced)
            case .string:
                attr.foregroundColor = NSColor(SyntaxColors.string)
            case .number:
                attr.foregroundColor = NSColor(SyntaxColors.number)
            case .type:
                attr.foregroundColor = NSColor(SyntaxColors.type)
            case .function:
                attr.foregroundColor = NSColor(SyntaxColors.function)
            case .comment:
                attr.foregroundColor = NSColor(SyntaxColors.comment)
            case .plain:
                attr.foregroundColor = NSColor(SyntaxColors.plain)
            }
            result.append(attr)
        }

        return result
    }

    // MARK: - Thinking Block

    private func thinkingBlockView(content: String, blockId: String) -> some View {
        let isCollapsed = collapsedThinking.contains(blockId)
        let lines = content.components(separatedBy: "\n")
        let preview = lines.prefix(3).joined(separator: "\n")
        let lineCount = lines.count

        return VStack(alignment: .leading, spacing: 0) {
            // Header
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isCollapsed {
                        collapsedThinking.remove(blockId)
                    } else {
                        collapsedThinking.insert(blockId)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ThinkingColors.accent)

                    Text("Reasoning")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ThinkingColors.accent)

                    if lineCount > 3 {
                        Text("\(lineCount) lines")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.quaternary)
                    }

                    Spacer()

                    Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.quaternary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !isCollapsed {
                Divider().opacity(0.2)

                ScrollView(.vertical, showsIndicators: true) {
                    Text(content)
                        .font(.system(size: 12))
                        .foregroundStyle(ThinkingColors.text)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(maxHeight: 300)
            } else {
                // Collapsed preview
                Text(preview + (lineCount > 3 ? "..." : ""))
                    .font(.system(size: 11.5))
                    .foregroundStyle(ThinkingColors.textMuted)
                    .lineLimit(2)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
        }
        .background(ThinkingColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(ThinkingColors.border, lineWidth: 0.5)
        )
    }

    // MARK: - Heading

    private func headingView(level: Int, text: String) -> some View {
        HStack(spacing: 8) {
            if level <= 2 {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.accentColor.opacity(level == 1 ? 0.6 : 0.35))
                    .frame(width: 3)
                    .padding(.vertical, 2)
            }
            Text(buildAttributedString(from: text))
                .font(headingFont(level: level))
                .foregroundStyle(level <= 2 ? .primary : .secondary)
        }
    }

    private func headingFont(level: Int) -> Font {
        switch level {
        case 1: return .system(size: 18, weight: .bold)
        case 2: return .system(size: 15, weight: .bold)
        case 3: return .system(size: 13, weight: .bold)
        default: return .system(size: 13, weight: .semibold)
        }
    }

    // MARK: - Blockquote

    private func blockquoteView(text: String) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.secondary.opacity(0.3))
                .frame(width: 3)

            Text(buildAttributedString(from: text))
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .textSelection(.enabled)
        }
        .padding(.vertical, 4)
        .padding(.leading, 4)
    }
}

// MARK: - Block Parser

private enum MarkdownBlockParser {
    static func parse(_ content: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(
            String.init)
        var i = 0
        var textBuffer: [String] = []

        func flushText() {
            let joined = textBuffer.joined(separator: "\n")
            if !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                blocks.append(.text(joined))
            }
            textBuffer.removeAll()
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Thinking blocks: <thinking>, <Thinking>, ```thinking
            if trimmed.lowercased().hasPrefix("<thinking>") || trimmed == "```thinking" {
                flushText()
                let isXml = trimmed.lowercased().hasPrefix("<thinking>")
                let closingTag = isXml ? "</thinking>" : "```"
                var thinkContent: [String] = []
                // If there's content on the same line after <thinking>
                let afterTag =
                    isXml
                    ? String(trimmed.dropFirst("<thinking>".count))
                    : ""
                if !afterTag.trimmingCharacters(in: .whitespaces).isEmpty {
                    thinkContent.append(afterTag)
                }
                i += 1
                while i < lines.count {
                    let l = lines[i].trimmingCharacters(in: .whitespaces)
                    if l.lowercased().hasPrefix(closingTag.lowercased()) {
                        break
                    }
                    thinkContent.append(lines[i])
                    i += 1
                }
                blocks.append(.thinking(content: thinkContent.joined(separator: "\n")))
                i += 1
                continue
            }

            // Fenced code blocks: ```language
            if trimmed.hasPrefix("```") {
                flushText()
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count {
                    if lines[i].trimmingCharacters(in: .whitespaces) == "```" {
                        break
                    }
                    codeLines.append(lines[i])
                    i += 1
                }
                blocks.append(
                    .codeBlock(
                        language: lang.isEmpty ? nil : lang,
                        code: codeLines.joined(separator: "\n")
                    ))
                i += 1
                continue
            }

            // Headings
            if trimmed.hasPrefix("#") {
                let level = trimmed.prefix(while: { $0 == "#" }).count
                if level >= 1 && level <= 6 {
                    let headingText = String(trimmed.dropFirst(level)).trimmingCharacters(
                        in: .whitespaces)
                    if !headingText.isEmpty {
                        flushText()
                        blocks.append(.heading(level: level, text: headingText))
                        i += 1
                        continue
                    }
                }
            }

            // Horizontal rule
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushText()
                blocks.append(.horizontalRule)
                i += 1
                continue
            }

            // Blockquote
            if trimmed.hasPrefix("> ") {
                flushText()
                var quoteLines: [String] = []
                while i < lines.count {
                    let ql = lines[i].trimmingCharacters(in: .whitespaces)
                    if ql.hasPrefix("> ") {
                        quoteLines.append(String(ql.dropFirst(2)))
                    } else if ql == ">" {
                        quoteLines.append("")
                    } else {
                        break
                    }
                    i += 1
                }
                blocks.append(.blockquote(quoteLines.joined(separator: "\n")))
                continue
            }

            // Regular text
            textBuffer.append(line)
            i += 1
        }

        flushText()
        return blocks
    }
}

// MARK: - Inline Text Scanner

private enum InlineSegment {
    case plain(String)
    case bold(String)
    case italic(String)
    case boldItalic(String)
    case inlineCode(String)
    case link(title: String, url: String)
    case strikethrough(String)
}

private struct InlineScanner {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    func scan() -> [InlineSegment] {
        var segments: [InlineSegment] = []
        var remaining = text[text.startIndex..<text.endIndex]
        var buffer = ""

        func flushBuffer() {
            if !buffer.isEmpty {
                segments.append(.plain(buffer))
                buffer = ""
            }
        }

        while !remaining.isEmpty {
            // Inline code: `code`
            if remaining.hasPrefix("`") && !remaining.hasPrefix("```") {
                if let endIndex = remaining.dropFirst().firstIndex(of: "`") {
                    flushBuffer()
                    let code = String(
                        remaining[remaining.index(after: remaining.startIndex)..<endIndex])
                    segments.append(.inlineCode(code))
                    remaining = remaining[remaining.index(after: endIndex)..<remaining.endIndex]
                    continue
                }
            }

            // Strikethrough: ~~text~~
            if remaining.hasPrefix("~~") {
                let after = remaining.dropFirst(2)
                if let range = after.range(of: "~~") {
                    flushBuffer()
                    let inner = String(after[after.startIndex..<range.lowerBound])
                    segments.append(.strikethrough(inner))
                    remaining = after[range.upperBound..<after.endIndex]
                    continue
                }
            }

            // Bold+italic: ***text*** or ___text___
            if remaining.hasPrefix("***") || remaining.hasPrefix("___") {
                let marker = String(remaining.prefix(3))
                let after = remaining.dropFirst(3)
                if let range = after.range(of: marker) {
                    flushBuffer()
                    let inner = String(after[after.startIndex..<range.lowerBound])
                    segments.append(.boldItalic(inner))
                    remaining = after[range.upperBound..<after.endIndex]
                    continue
                }
            }

            // Bold: **text** or __text__
            if remaining.hasPrefix("**") || remaining.hasPrefix("__") {
                let marker = String(remaining.prefix(2))
                let after = remaining.dropFirst(2)
                if let range = after.range(of: marker) {
                    flushBuffer()
                    let inner = String(after[after.startIndex..<range.lowerBound])
                    segments.append(.bold(inner))
                    remaining = after[range.upperBound..<after.endIndex]
                    continue
                }
            }

            // Italic: *text* or _text_ (but not ** or __)
            if (remaining.hasPrefix("*") && !remaining.hasPrefix("**"))
                || (remaining.hasPrefix("_") && !remaining.hasPrefix("__"))
            {
                let marker = String(remaining.prefix(1))
                let after = remaining.dropFirst(1)
                if let idx = after.firstIndex(of: Character(marker)) {
                    // Ensure the marker is not preceded by a space (common false positive)
                    let inner = String(after[after.startIndex..<idx])
                    if !inner.isEmpty && !inner.hasPrefix(" ") && !inner.hasSuffix(" ") {
                        flushBuffer()
                        segments.append(.italic(inner))
                        remaining = after[after.index(after: idx)..<after.endIndex]
                        continue
                    }
                }
            }

            // Markdown link: [title](url)
            if remaining.hasPrefix("[") {
                let after = remaining.dropFirst()
                if let closeBracket = after.firstIndex(of: "]") {
                    let title = String(after[after.startIndex..<closeBracket])
                    let afterBracket = after[after.index(after: closeBracket)..<after.endIndex]
                    if afterBracket.hasPrefix("(") {
                        let urlPart = afterBracket.dropFirst()
                        if let closeParen = urlPart.firstIndex(of: ")") {
                            let url = String(urlPart[urlPart.startIndex..<closeParen])
                            flushBuffer()
                            segments.append(.link(title: title, url: url))
                            remaining = urlPart[urlPart.index(after: closeParen)..<urlPart.endIndex]
                            continue
                        }
                    }
                }
            }

            buffer.append(remaining.removeFirst())
        }

        flushBuffer()
        return segments
    }
}

// MARK: - Lightweight Tokenizer for Syntax Highlighting

private enum TokenKind {
    case keyword, string, number, type, function, comment, plain
}

private struct Token {
    let text: String
    let kind: TokenKind
}

private func tokenizeLine(_ line: String, language: String?) -> [Token] {
    let lang = (language ?? "").lowercased()

    // Keywords by language family
    let keywords: Set<String> = {
        switch lang {
        case "swift":
            return [
                "import", "func", "var", "let", "struct", "class", "enum", "protocol",
                "extension", "if", "else", "guard", "return", "for", "in", "while",
                "switch", "case", "default", "break", "continue", "throw", "throws",
                "try", "catch", "async", "await", "public", "private", "internal",
                "fileprivate", "open", "static", "final", "override", "mutating",
                "weak", "unowned", "lazy", "some", "any", "where", "typealias",
                "associatedtype", "init", "deinit", "self", "Self", "super", "nil",
                "true", "false", "as", "is", "do", "repeat", "defer", "inout",
                "@MainActor", "@Published", "@State", "@Binding", "@ObservedObject",
                "@EnvironmentObject", "@Environment", "@AppStorage", "@ViewBuilder",
                "@Sendable", "@escaping", "@discardableResult", "@available",
            ]
        case "typescript", "ts", "tsx", "javascript", "js", "jsx":
            return [
                "import", "export", "from", "const", "let", "var", "function", "class",
                "interface", "type", "enum", "if", "else", "return", "for", "while",
                "switch", "case", "default", "break", "continue", "throw", "try",
                "catch", "finally", "async", "await", "new", "this", "super", "null",
                "undefined", "true", "false", "typeof", "instanceof", "void", "delete",
                "in", "of", "yield", "extends", "implements", "static", "private",
                "public", "protected", "readonly", "abstract", "as", "satisfies",
                "keyof", "infer", "declare", "module", "namespace",
            ]
        case "python", "py":
            return [
                "import", "from", "def", "class", "if", "elif", "else", "return",
                "for", "while", "with", "as", "try", "except", "finally", "raise",
                "pass", "break", "continue", "and", "or", "not", "in", "is", "None",
                "True", "False", "lambda", "yield", "async", "await", "global",
                "nonlocal", "assert", "del", "self", "cls", "@staticmethod",
                "@classmethod", "@property", "@abstractmethod",
            ]
        case "rust", "rs":
            return [
                "fn", "let", "mut", "const", "struct", "enum", "impl", "trait", "pub",
                "use", "mod", "crate", "self", "super", "if", "else", "match", "for",
                "while", "loop", "return", "break", "continue", "where", "async",
                "await", "move", "ref", "type", "static", "unsafe", "extern", "dyn",
                "true", "false", "as", "in",
            ]
        case "go":
            return [
                "package", "import", "func", "var", "const", "type", "struct",
                "interface", "if", "else", "for", "range", "switch", "case", "default",
                "return", "break", "continue", "go", "defer", "select", "chan", "map",
                "make", "new", "nil", "true", "false", "append", "len", "cap",
            ]
        case "bash", "sh", "zsh", "shell":
            return [
                "if", "then", "else", "elif", "fi", "for", "while", "do", "done",
                "case", "esac", "function", "return", "exit", "export", "local",
                "readonly", "declare", "set", "unset", "shift", "source", "echo",
                "cd", "ls", "rm", "cp", "mv", "mkdir", "grep", "sed", "awk",
                "cat", "chmod", "chown", "curl", "wget", "git", "npm", "yarn",
                "brew", "pip", "python", "node", "swift", "cargo",
            ]
        default:
            return [
                "import", "func", "function", "def", "class", "struct", "enum",
                "interface", "type", "var", "let", "const", "if", "else", "return",
                "for", "while", "switch", "case", "default", "break", "continue",
                "throw", "try", "catch", "async", "await", "new", "this", "self",
                "null", "nil", "None", "true", "false", "public", "private",
                "static", "final", "override", "extends", "implements",
            ]
        }
    }()

    let typePattern: Set<String> = [
        "String", "Int", "Bool", "Double", "Float", "Array",
        "Dictionary", "Set", "Optional", "Result", "UUID",
        "Date", "URL", "Data", "Error", "View", "Color",
        "some", "any", "void", "number", "string", "boolean",
        "Promise", "Observable", "Record", "Partial",
    ]

    var tokens: [Token] = []
    var remaining = line[line.startIndex..<line.endIndex]
    var plainBuffer = ""

    func flushPlain() {
        if !plainBuffer.isEmpty {
            tokens.append(Token(text: plainBuffer, kind: .plain))
            plainBuffer = ""
        }
    }

    while !remaining.isEmpty {
        // String literals: "..." or '...'
        if remaining.first == "\"" || remaining.first == "'" {
            flushPlain()
            let quote = remaining.first!
            var str = String(quote)
            var iter = remaining.dropFirst()
            var escaped = false
            while !iter.isEmpty {
                let ch = iter.first!
                str.append(ch)
                iter = iter.dropFirst()
                if escaped {
                    escaped = false
                    continue
                }
                if ch == "\\" {
                    escaped = true
                    continue
                }
                if ch == quote {
                    break
                }
            }
            tokens.append(Token(text: str, kind: .string))
            remaining = iter
            continue
        }

        // Numbers
        if let first = remaining.first,
            first.isNumber || (first == "." && remaining.dropFirst().first?.isNumber == true)
        {
            flushPlain()
            var num = ""
            var iter = remaining
            while let ch = iter.first,
                ch.isNumber || ch == "." || ch == "_" || ch == "x" || ch == "b"
                    || (ch.isHexDigit && num.contains("0x"))
            {
                num.append(ch)
                iter = iter.dropFirst()
            }
            tokens.append(Token(text: num, kind: .number))
            remaining = iter
            continue
        }

        // Word boundaries: keywords, types, functions
        if let first = remaining.first, first.isLetter || first == "_" || first == "@" {
            flushPlain()
            var word = ""
            var iter = remaining
            while let ch = iter.first, ch.isLetter || ch.isNumber || ch == "_" || ch == "@" {
                word.append(ch)
                iter = iter.dropFirst()
            }

            if keywords.contains(word) {
                tokens.append(Token(text: word, kind: .keyword))
            } else if typePattern.contains(word)
                || (word.first?.isUppercase == true && word.count > 1)
            {
                tokens.append(Token(text: word, kind: .type))
            } else if iter.first == "(" {
                tokens.append(Token(text: word, kind: .function))
            } else {
                tokens.append(Token(text: word, kind: .plain))
            }
            remaining = iter
            continue
        }

        // Inline comment: //
        if remaining.hasPrefix("//") {
            flushPlain()
            tokens.append(Token(text: String(remaining), kind: .comment))
            return tokens
        }

        // Everything else
        plainBuffer.append(remaining.removeFirst())
    }

    flushPlain()
    return tokens
}

// MARK: - Color Definitions

private enum SyntaxColors {
    static let keyword = codigoAdaptive(
        NSColor(red: 0.68, green: 0.33, blue: 0.85, alpha: 1),  // purple light
        NSColor(red: 0.78, green: 0.50, blue: 0.96, alpha: 1)  // purple dark
    )
    static let string = codigoAdaptive(
        NSColor(red: 0.16, green: 0.56, blue: 0.28, alpha: 1),  // green light
        NSColor(red: 0.38, green: 0.78, blue: 0.46, alpha: 1)  // green dark
    )
    static let number = codigoAdaptive(
        NSColor(red: 0.11, green: 0.43, blue: 0.69, alpha: 1),  // blue light
        NSColor(red: 0.51, green: 0.73, blue: 0.96, alpha: 1)  // blue dark
    )
    static let type = codigoAdaptive(
        NSColor(red: 0.13, green: 0.55, blue: 0.55, alpha: 1),  // teal light
        NSColor(red: 0.40, green: 0.82, blue: 0.82, alpha: 1)  // teal dark
    )
    static let function = codigoAdaptive(
        NSColor(red: 0.16, green: 0.40, blue: 0.72, alpha: 1),  // blue light
        NSColor(red: 0.55, green: 0.76, blue: 0.98, alpha: 1)  // blue dark
    )
    static let comment = codigoAdaptive(
        NSColor(red: 0.45, green: 0.50, blue: 0.55, alpha: 1),  // gray light
        NSColor(red: 0.48, green: 0.54, blue: 0.60, alpha: 1)  // gray dark
    )
    static let plain = codigoAdaptive(
        NSColor(red: 0.15, green: 0.16, blue: 0.18, alpha: 1),  // near-black light
        NSColor(red: 0.85, green: 0.87, blue: 0.90, alpha: 1)  // near-white dark
    )
    static let added = codigoAdaptive(
        NSColor(red: 0.10, green: 0.52, blue: 0.22, alpha: 1),
        NSColor(red: 0.35, green: 0.78, blue: 0.45, alpha: 1)
    )
    static let addedBg = codigoAdaptive(
        NSColor(red: 0.85, green: 0.96, blue: 0.87, alpha: 1),
        NSColor(red: 0.10, green: 0.22, blue: 0.12, alpha: 0.4)
    )
    static let removed = codigoAdaptive(
        NSColor(red: 0.68, green: 0.15, blue: 0.15, alpha: 1),
        NSColor(red: 0.92, green: 0.42, blue: 0.42, alpha: 1)
    )
    static let removedBg = codigoAdaptive(
        NSColor(red: 0.98, green: 0.88, blue: 0.88, alpha: 1),
        NSColor(red: 0.28, green: 0.10, blue: 0.10, alpha: 0.4)
    )
}

private enum CodeBlockColors {
    static let background = codigoAdaptive(
        NSColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1),
        NSColor(red: 0.09, green: 0.10, blue: 0.12, alpha: 1)
    )
    static let border = codigoAdaptive(
        NSColor(red: 0.88, green: 0.89, blue: 0.91, alpha: 1),
        NSColor(red: 0.20, green: 0.21, blue: 0.24, alpha: 1)
    )
}

private enum ThinkingColors {
    static let background = codigoAdaptive(
        NSColor(red: 0.96, green: 0.95, blue: 1.0, alpha: 1),
        NSColor(red: 0.11, green: 0.09, blue: 0.16, alpha: 1)
    )
    static let border = codigoAdaptive(
        NSColor(red: 0.88, green: 0.85, blue: 0.96, alpha: 1),
        NSColor(red: 0.22, green: 0.18, blue: 0.32, alpha: 1)
    )
    static let accent = codigoAdaptive(
        NSColor(red: 0.52, green: 0.36, blue: 0.80, alpha: 1),
        NSColor(red: 0.68, green: 0.55, blue: 0.92, alpha: 1)
    )
    static let text = codigoAdaptive(
        NSColor(red: 0.30, green: 0.28, blue: 0.38, alpha: 1),
        NSColor(red: 0.72, green: 0.70, blue: 0.82, alpha: 1)
    )
    static let textMuted = codigoAdaptive(
        NSColor(red: 0.50, green: 0.48, blue: 0.58, alpha: 1),
        NSColor(red: 0.55, green: 0.52, blue: 0.65, alpha: 1)
    )
}
