import SwiftUI

// MARK: - Premium Block-level Markdown Renderer

struct MarkdownContentView: View {
    let content: String
    let context: ProjectContext?
    let onFileClicked: (String) -> Void
    var textAlignment: TextAlignment = .leading
    var isStreaming: Bool = false
    var aggressiveSanitization: Bool? = nil

    private var shouldUseAggressiveSanitization: Bool {
        aggressiveSanitization ?? !isStreaming
    }

    private var displayContent: String {
        Self.normalizeAssistantDisplayLayout(
            ChatStore.stripCoderideMarkers(content, aggressive: shouldUseAggressiveSanitization)
        )
            .replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: .regularExpression)
    }

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Premium Design Tokens

    private var bodyFont: CGFloat { 13.5 }
    private var bodyLineSpacing: CGFloat { 6.5 }

    // Text
    private var textPrimary: Color { .primary.opacity(0.93) }
    private var textSecondary: Color { .primary.opacity(0.55) }

    // Accent — muted periwinkle/indigo for headings & bullets
    private var accentColor: Color {
        colorScheme == .dark
            ? Color(red: 0.55, green: 0.63, blue: 0.95)
            : Color(red: 0.30, green: 0.38, blue: 0.75)
    }

    // Code
    private var codeBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.075, green: 0.082, blue: 0.110)
            : Color(red: 0.95, green: 0.955, blue: 0.97)
    }
    private var codeBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.06)
    }
    private var inlineCodeColor: Color {
        colorScheme == .dark
            ? Color(red: 0.90, green: 0.64, blue: 0.44)
            : Color(red: 0.70, green: 0.33, blue: 0.12)
    }
    private var inlineCodeBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.90, green: 0.64, blue: 0.44).opacity(0.10)
            : Color(red: 0.70, green: 0.33, blue: 0.12).opacity(0.07)
    }

    // Headings
    private var h1Color: Color {
        colorScheme == .dark
            ? Color(red: 0.94, green: 0.95, blue: 1.0)
            : Color(red: 0.08, green: 0.10, blue: 0.16)
    }
    private var h2Color: Color {
        colorScheme == .dark
            ? Color(red: 0.88, green: 0.90, blue: 0.98)
            : Color(red: 0.12, green: 0.14, blue: 0.22)
    }
    private var h3Color: Color {
        colorScheme == .dark
            ? Color(red: 0.82, green: 0.85, blue: 0.95)
            : Color(red: 0.15, green: 0.18, blue: 0.28)
    }

    // Dividers
    private var dividerColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05)
    }

    // Blockquote
    private var quoteBarColor: Color { accentColor.opacity(0.45) }
    private var quoteBg: Color {
        colorScheme == .dark
            ? accentColor.opacity(0.04)
            : accentColor.opacity(0.03)
    }

    // MARK: - Body

    var body: some View {
        if isStreaming {
            streamingBody
        } else {
            fullMarkdownBody
        }
    }

    // MARK: - Streaming Body (fast, no block parsing)

    private var streamingBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            let text = displayContent
            if text.isEmpty {
                StreamingCursorView()
            } else {
                (Text(buildStreamingAttributed(text))
                    + Text(" \u{258C}")
                        .font(.system(size: bodyFont))
                        .foregroundColor(textPrimary.opacity(0.45)))
                    .font(.system(size: bodyFont))
                    .foregroundStyle(textPrimary)
                    .lineSpacing(bodyLineSpacing)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func buildStreamingAttributed(_ text: String) -> AttributedString {
        var result: AttributedString
        if let markdown = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        ) {
            result = markdown
        } else {
            result = AttributedString(text)
        }
        for run in result.runs {
            let range = run.range
            guard let intent = run.inlinePresentationIntent else { continue }
            if intent.contains(.code) {
                result[range].font = .system(size: max(bodyFont - 1, 11), weight: .medium, design: .monospaced)
                result[range].backgroundColor = NSColor(inlineCodeBackground)
                result[range].foregroundColor = NSColor(inlineCodeColor)
            }
        }
        return result
    }

    // MARK: - Full Markdown Body (block-level)

    private var fullMarkdownBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            let blocks = parseBlocks()
            ForEach(Array(blocks.enumerated()), id: \.offset) { idx, block in
                blockView(for: block, prevBlock: idx > 0 ? blocks[idx - 1] : nil)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Block Types

    enum MarkdownBlock: Equatable {
        case heading(level: Int, text: String)
        case paragraph(text: String)
        case bulletItem(text: String, indent: Int)
        case numberedItem(number: String, text: String, indent: Int)
        case codeBlock(language: String, code: String)
        case mermaid(code: String)
        case horizontalRule
        case blockquote(text: String)
        case table(headers: [String], rows: [[String]])
        case spacer
    }

    // MARK: - Context-Aware Spacing

    private func topSpacing(for block: MarkdownBlock, prev: MarkdownBlock?) -> CGFloat {
        guard let prev else { return 0 }
        switch block {
        case .heading(let level, _):
            switch prev {
            case .heading: return level == 1 ? 24 : 16
            default: return level == 1 ? 28 : (level == 2 ? 22 : 16)
            }
        case .paragraph:
            switch prev {
            case .heading: return 8
            case .bulletItem, .numberedItem: return 12
            case .codeBlock: return 14
            case .paragraph: return 10
            case .blockquote: return 12
            default: return 8
            }
        case .bulletItem, .numberedItem:
            switch prev {
            case .heading: return 10
            case .paragraph: return 8
            case .bulletItem, .numberedItem: return 3
            case .codeBlock, .mermaid: return 10
            default: return 8
            }
        case .codeBlock:
            return 14
        case .mermaid:
            return 14
        case .horizontalRule:
            return 16
        case .blockquote:
            return 12
        case .table:
            return 14
        case .spacer:
            return 0
        }
    }

    // MARK: - Block Rendering

    @ViewBuilder
    private func blockView(for block: MarkdownBlock, prevBlock: MarkdownBlock?) -> some View {
        let topPad = topSpacing(for: block, prev: prevBlock)

        switch block {
        case .heading(let level, let text):
            headingView(level: level, text: text)
                .padding(.top, topPad)

        case .paragraph(let text):
            inlineMarkdown(text)
                .padding(.top, topPad)

        case .bulletItem(let text, let indent):
            bulletItemView(text: text, indent: indent)
                .padding(.top, topPad)

        case .numberedItem(let number, let text, let indent):
            numberedItemView(number: number, text: text, indent: indent)
                .padding(.top, topPad)

        case .codeBlock(let language, let code):
            codeBlockView(language: language, code: code)
                .padding(.top, topPad)

        case .mermaid(let code):
            mermaidBlockView(code: code)
                .padding(.top, topPad)

        case .table(let headers, let rows):
            tableView(headers: headers, rows: rows)
                .padding(.top, topPad)

        case .horizontalRule:
            horizontalRuleView
                .padding(.top, topPad)

        case .blockquote(let text):
            blockquoteView(text: text)
                .padding(.top, topPad)

        case .spacer:
            Spacer().frame(height: 4)
        }
    }

    // MARK: - Headings

    private func headingView(level: Int, text: String) -> some View {
        let size: CGFloat
        let weight: Font.Weight
        let color: Color
        let letterSpacing: CGFloat

        switch level {
        case 1:
            size = 21; weight = .bold; color = h1Color; letterSpacing = -0.3
        case 2:
            size = 17.5; weight = .bold; color = h2Color; letterSpacing = -0.2
        case 3:
            size = 15; weight = .semibold; color = h3Color; letterSpacing = -0.1
        default:
            size = 13.5; weight = .semibold; color = h3Color; letterSpacing = 0
        }

        return VStack(alignment: .leading, spacing: level <= 2 ? 10 : 4) {
            inlineMarkdown(text, fontSize: size, fontWeight: weight, color: color)
                .tracking(letterSpacing)
            if level == 1 {
                // Premium gradient rule under h1
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                accentColor.opacity(0.40),
                                accentColor.opacity(0.15),
                                dividerColor,
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1.5)
                    .frame(maxWidth: 320)
            } else if level == 2 {
                // Subtle rule under h2
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                accentColor.opacity(0.20),
                                dividerColor,
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: 1)
                    .frame(maxWidth: 240)
            }
        }
    }

    // MARK: - Bullet Item

    private func bulletItemView(text: String, indent: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            // Elegant bullet: small rounded square for indent 0, circle for nested
            if indent == 0 {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(accentColor.opacity(0.7))
                    .frame(width: 5, height: 5)
                    .offset(y: 1)
            } else {
                Circle()
                    .strokeBorder(accentColor.opacity(0.5), lineWidth: 1)
                    .frame(width: 4.5, height: 4.5)
                    .offset(y: 1)
            }
            inlineMarkdown(text)
        }
        .padding(.leading, 4 + CGFloat(indent) * 22)
        .padding(.vertical, 4)
    }

    // MARK: - Numbered Item

    private func numberedItemView(number: String, text: String, indent: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number).")
                .font(.system(size: bodyFont, weight: .bold, design: .rounded))
                .foregroundStyle(accentColor.opacity(0.8))
                .frame(minWidth: 22, alignment: .trailing)
            inlineMarkdown(text)
        }
        .padding(.leading, CGFloat(indent) * 22)
        .padding(.vertical, 4)
    }

    // MARK: - Horizontal Rule

    private var horizontalRuleView: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            dividerColor.opacity(0),
                            accentColor.opacity(0.15),
                            dividerColor.opacity(0),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Blockquote

    private func blockquoteView(text: String) -> some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(quoteBarColor)
                .frame(width: 3)
            inlineMarkdown(text, color: textSecondary)
                .padding(.leading, 16)
                .padding(.vertical, 10)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(quoteBg)
        )
    }

    // MARK: - Inline Markdown Text

    @ViewBuilder
    private func inlineMarkdown(
        _ text: String,
        fontSize: CGFloat = 0,
        fontWeight: Font.Weight = .regular,
        color: Color? = nil
    ) -> some View {
        let sz = fontSize == 0 ? bodyFont : fontSize
        let attributed = buildInlineAttributed(text, fontSize: sz, fontWeight: fontWeight, color: color)
        Text(attributed)
            .environment(\.openURL, OpenURLAction { url in
                if url.isFileURL { onFileClicked(url.path); return .handled }
                return .systemAction(url)
            })
            .font(.system(size: sz, weight: fontWeight))
            .foregroundStyle(color ?? textPrimary)
            .lineSpacing(bodyLineSpacing)
            .textSelection(.enabled)
    }

    // MARK: - Code Block

    private func codeBlockView(language: String, code: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar
            HStack {
                if !language.isEmpty {
                    Text(language.lowercased())
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(accentColor.opacity(0.6))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(accentColor.opacity(0.08), in: Capsule())
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 9))
                        Text("Copy")
                            .font(.system(size: 9.5, weight: .medium))
                    }
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                }
                .buttonStyle(.plain)
                .help("Copy code")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                colorScheme == .dark
                    ? Color.white.opacity(0.02)
                    : Color.black.opacity(0.015)
            )

            Rectangle()
                .fill(codeBorder)
                .frame(height: 0.5)

            // Code content
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.85))
                    .textSelection(.enabled)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(codeBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(codeBorder, lineWidth: 0.5)
        )
    }

    private func mermaidBlockView(code: String) -> some View {
        MermaidDiagramView(
            mermaidCode: code,
            accentColor: accentColor
        )
    }

    // MARK: - Inline AttributedString Builder

    private func buildInlineAttributed(
        _ text: String,
        fontSize: CGFloat,
        fontWeight: Font.Weight,
        color: Color?
    ) -> AttributedString {
        var result: AttributedString
        if let markdown = try? AttributedString(
            markdown: text,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .full,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        ) {
            result = markdown
        } else {
            result = AttributedString(text)
        }

        // Style inline code + bold + italic
        for run in result.runs {
            let range = run.range
            if let intent = run.inlinePresentationIntent {
                if intent.contains(.code) {
                    result[range].font = .system(
                        size: max(fontSize - 1, 11),
                        weight: .medium,
                        design: .monospaced
                    )
                    result[range].backgroundColor = NSColor(inlineCodeBackground)
                    result[range].foregroundColor = NSColor(inlineCodeColor)
                }
                // Bold gets slightly brighter
                if intent.contains(.stronglyEmphasized) && !intent.contains(.code) {
                    result[range].foregroundColor = NSColor(color ?? h1Color)
                }
            }
        }

        // File links
        let pattern = #"([a-zA-Z0-9_][a-zA-Z0-9_/.-]*\.(swift|ts|tsx|js|jsx|py|json|md|html|css|yaml|yml|xml|plist|strings)(?::\d+)?)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return result }
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        for match in regex.matches(in: text, range: fullRange) {
            let fileRef = nsText.substring(with: match.range)
            guard let strRange = Range(match.range, in: text) else { continue }
            guard let lower = AttributedString.Index(strRange.lowerBound, within: result),
                  let upper = AttributedString.Index(strRange.upperBound, within: result) else { continue }
            result[lower..<upper].foregroundColor = NSColor(accentColor)
            result[lower..<upper].underlineStyle = .single
            result[lower..<upper].link = URL(fileURLWithPath: resolvePath(fileRef))
        }
        return result
    }

    // MARK: - Block Parser

    private func parseBlocks() -> [MarkdownBlock] {
        let lines = displayContent.components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var i = 0
        var paragraphBuffer: [String] = []

        func flushParagraph() {
            let text = paragraphBuffer.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if !text.isEmpty {
                blocks.append(.paragraph(text: text))
            }
            paragraphBuffer.removeAll()
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Empty line
            if trimmed.isEmpty {
                flushParagraph()
                if blocks.last != .spacer && blocks.last != nil {
                    blocks.append(.spacer)
                }
                i += 1
                continue
            }

            // Horizontal rule
            if (trimmed == "---" || trimmed == "***" || trimmed == "___") && !trimmed.contains("|") {
                flushParagraph()
                blocks.append(.horizontalRule)
                i += 1
                continue
            }

            // Table
            if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") && trimmed.filter({ $0 == "|" }).count >= 2 {
                let nextIdx = i + 1
                if nextIdx < lines.count {
                    let nextTrimmed = lines[nextIdx].trimmingCharacters(in: .whitespaces)
                    let isSeparator = nextTrimmed.hasPrefix("|") && nextTrimmed.contains("-")
                    if isSeparator {
                        flushParagraph()
                        let headers = parsePipeRow(trimmed)
                        i += 2
                        var tableRows: [[String]] = []
                        while i < lines.count {
                            let rowTrimmed = lines[i].trimmingCharacters(in: .whitespaces)
                            guard rowTrimmed.hasPrefix("|") && rowTrimmed.hasSuffix("|") else { break }
                            tableRows.append(parsePipeRow(rowTrimmed))
                            i += 1
                        }
                        blocks.append(.table(headers: headers, rows: tableRows))
                        continue
                    }
                }
            }

            // Fenced code block
            if trimmed.hasPrefix("```") {
                flushParagraph()
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count {
                    if lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        i += 1
                        break
                    }
                    codeLines.append(lines[i])
                    i += 1
                }
                let code = codeLines.joined(separator: "\n")
                if lang.lowercased() == "mermaid" {
                    blocks.append(.mermaid(code: code))
                } else {
                    blocks.append(.codeBlock(language: lang, code: code))
                }
                continue
            }

            // Blockquote
            if trimmed.hasPrefix("> ") || trimmed == ">" {
                flushParagraph()
                var quoteLines: [String] = []
                while i < lines.count {
                    let l = lines[i].trimmingCharacters(in: .whitespaces)
                    if l.hasPrefix("> ") {
                        quoteLines.append(String(l.dropFirst(2)))
                        i += 1
                    } else if l == ">" {
                        quoteLines.append("")
                        i += 1
                    } else if l.hasPrefix(">") {
                        quoteLines.append(String(l.dropFirst(1)))
                        i += 1
                    } else { break }
                }
                blocks.append(.blockquote(text: quoteLines.joined(separator: "\n")))
                continue
            }

            // Heading
            if trimmed.hasPrefix("#") {
                let hashes = trimmed.prefix(while: { $0 == "#" })
                let level = hashes.count
                if level <= 6 {
                    let rest = trimmed.dropFirst(level)
                    if rest.first == " " {
                        let text = String(rest.dropFirst()).trimmingCharacters(in: .whitespaces)
                        if !text.isEmpty {
                            flushParagraph()
                            blocks.append(.heading(level: level, text: text))
                            i += 1
                            continue
                        }
                    }
                }
            }

            // Bullet list
            let leadingSpaces = line.prefix(while: { $0 == " " }).count
            let indent = leadingSpaces / 2
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
                let text = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if !text.isEmpty {
                    flushParagraph()
                    blocks.append(.bulletItem(text: text, indent: indent))
                    i += 1
                    continue
                }
            }

            // Numbered list
            if let dotIdx = trimmed.firstIndex(of: "."),
               trimmed.startIndex < dotIdx,
               let num = Int(trimmed[trimmed.startIndex..<dotIdx])
            {
                let afterDot = trimmed.index(after: dotIdx)
                if afterDot < trimmed.endIndex, trimmed[afterDot] == " " {
                    let text = String(trimmed[trimmed.index(after: afterDot)...])
                        .trimmingCharacters(in: .whitespaces)
                    if !text.isEmpty {
                        flushParagraph()
                        blocks.append(.numberedItem(
                            number: String(num),
                            text: text,
                            indent: indent
                        ))
                        i += 1
                        continue
                    }
                }
            }

            // Regular text
            paragraphBuffer.append(trimmed)
            i += 1
        }

        flushParagraph()
        if blocks.last == .spacer { blocks.removeLast() }
        return blocks
    }

    // MARK: - Table Rendering

    private func tableView(headers: [String], rows: [[String]]) -> some View {
        let colCount = headers.count
        return VStack(spacing: 0) {
            // Header
            HStack(spacing: 0) {
                ForEach(Array(headers.enumerated()), id: \.offset) { idx, header in
                    Text(header)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(h2Color)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                    if idx < colCount - 1 {
                        Rectangle()
                            .fill(codeBorder)
                            .frame(width: 0.5)
                    }
                }
            }
            .background(accentColor.opacity(colorScheme == .dark ? 0.06 : 0.04))

            Rectangle().fill(codeBorder).frame(height: 0.5)

            // Data rows
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, row in
                HStack(spacing: 0) {
                    ForEach(0..<colCount, id: \.self) { colIdx in
                        let cellText = colIdx < row.count ? row[colIdx] : ""
                        inlineMarkdown(cellText, fontSize: 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                        if colIdx < colCount - 1 {
                            Rectangle()
                                .fill(codeBorder)
                                .frame(width: 0.5)
                        }
                    }
                }
                .background(
                    rowIdx % 2 == 1
                        ? codeBackground.opacity(0.5)
                        : Color.clear
                )

                if rowIdx < rows.count - 1 {
                    Rectangle().fill(codeBorder).frame(height: 0.5)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(codeBorder, lineWidth: 0.5)
        )
    }

    // MARK: - Helpers

    private func parsePipeRow(_ line: String) -> [String] {
        var text = line.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("|") { text = String(text.dropFirst()) }
        if text.hasSuffix("|") { text = String(text.dropLast()) }
        return text.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
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
            case .resolved(let path): return path
            case .ambiguous(let matches): return matches.first ?? t
            case .notFound: break
            }
        }
        return t
    }

    static func normalizeAssistantDisplayLayout(_ input: String) -> String {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return trimmedInput }

        let parts = splitByCodeFence(trimmedInput)
        let normalized = parts.map { part -> String in
            guard !part.isCodeFence else { return part.text }
            return normalizePlainMarkdownSegment(part.text)
        }.joined()

        return normalized
            .replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func splitByCodeFence(_ input: String) -> [(text: String, isCodeFence: Bool)] {
        var segments: [(String, Bool)] = []
        var cursor = input.startIndex
        var inFence = false

        while cursor < input.endIndex {
            guard let fenceRange = input[cursor...].range(of: "```") else {
                let rest = String(input[cursor...])
                if !rest.isEmpty {
                    segments.append((rest, inFence))
                }
                break
            }

            let before = String(input[cursor..<fenceRange.lowerBound])
            if !before.isEmpty {
                segments.append((before, inFence))
            }

            if let nextFence = input[fenceRange.upperBound...].range(of: "```") {
                let fenceChunk = String(input[fenceRange.lowerBound..<nextFence.upperBound])
                segments.append((fenceChunk, true))
                cursor = nextFence.upperBound
                inFence = false
            } else {
                let remainder = String(input[fenceRange.lowerBound...])
                segments.append((remainder, true))
                break
            }
        }

        return segments
    }

    private static func normalizePlainMarkdownSegment(_ segment: String) -> String {
        var out = segment

        // Separate inline numbered/bullet sections from previous prose.
        out = out.replacingOccurrences(
            of: #"([.!?])\s+(?=\d+\.\s+)"#,
            with: "$1\n\n",
            options: .regularExpression
        )
        out = out.replacingOccurrences(
            of: #"([.!?])\s+(?=[-*+]\s+)"#,
            with: "$1\n\n",
            options: .regularExpression
        )

        // Dense single-line paragraphs become multiple readable paragraphs.
        let lines = out.components(separatedBy: .newlines)
        let rebuilt = lines.map { line in
            normalizeDenseLine(line)
        }.joined(separator: "\n")

        return rebuilt
    }

    private static func normalizeDenseLine(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return line }

        // Keep already-structured markdown lines untouched.
        if isStructuredMarkdownLine(trimmed) {
            return line
        }

        guard !trimmed.contains("\n"), trimmed.count > 320 else {
            return line
        }

        let sentenceSplitPattern = #"(?<=[.!?])\s+(?=[A-ZÀ-ÖØ-Ý0-9])"#
        guard let regex = try? NSRegularExpression(pattern: sentenceSplitPattern, options: []) else {
            return line
        }
        let ns = trimmed as NSString
        let matches = regex.matches(in: trimmed, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return line }

        var sentences: [String] = []
        var cursor = trimmed.startIndex
        for match in matches {
            guard let range = Range(match.range, in: trimmed) else { continue }
            let sentence = String(trimmed[cursor..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            if !sentence.isEmpty {
                sentences.append(sentence)
            }
            cursor = range.upperBound
        }
        let last = String(trimmed[cursor...]).trimmingCharacters(in: .whitespaces)
        if !last.isEmpty { sentences.append(last) }
        guard sentences.count >= 4 else { return line }

        var chunks: [String] = []
        var current: [String] = []
        var currentLen = 0
        for sentence in sentences {
            let projected = currentLen + sentence.count + (current.isEmpty ? 0 : 1)
            if !current.isEmpty && projected > 220 {
                chunks.append(current.joined(separator: " "))
                current = [sentence]
                currentLen = sentence.count
            } else {
                current.append(sentence)
                currentLen = projected
            }
        }
        if !current.isEmpty {
            chunks.append(current.joined(separator: " "))
        }
        return chunks.joined(separator: "\n\n")
    }

    private static func isStructuredMarkdownLine(_ line: String) -> Bool {
        if line.hasPrefix("#") || line.hasPrefix(">") { return true }
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") { return true }
        if line.hasPrefix("|"), line.hasSuffix("|") { return true }
        if line == "---" || line == "***" || line == "___" { return true }

        let numberedPattern = #"^\d+\.\s+"#
        if let regex = try? NSRegularExpression(pattern: numberedPattern, options: []) {
            let ns = line as NSString
            let range = NSRange(location: 0, length: ns.length)
            return regex.firstMatch(in: line, options: [], range: range) != nil
        }
        return false
    }
}

// MARK: - Streaming Cursor

private struct StreamingCursorView: View {
    @State private var visible = true

    var body: some View {
        Text("\u{258C}")
            .font(.system(size: 13.5))
            .foregroundStyle(Color.primary.opacity(visible ? 0.7 : 0.15))
            .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: visible)
            .onAppear { visible = false }
    }
}
