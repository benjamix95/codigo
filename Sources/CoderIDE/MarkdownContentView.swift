import SwiftUI

// MARK: - Block-level Markdown Renderer (ChatGPT-style)

struct MarkdownContentView: View {
    let content: String
    let context: ProjectContext?
    let onFileClicked: (String) -> Void
    var textAlignment: TextAlignment = .leading

    private var displayContent: String {
        ChatStore.stripCoderideMarkers(content)
            .replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Design Tokens

    private var bodyFont: CGFloat { 13.5 }
    private var lineHeight: CGFloat { 6 }

    private var textPrimary: Color { .primary.opacity(0.92) }
    private var bulletColor: Color {
        colorScheme == .dark
            ? Color(red: 0.50, green: 0.62, blue: 0.90)
            : Color(red: 0.28, green: 0.38, blue: 0.72)
    }
    private var codeBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.09, green: 0.10, blue: 0.13)
            : Color(red: 0.95, green: 0.96, blue: 0.97)
    }
    private var codeBorder: Color {
        colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.06)
    }
    private var headingColor: Color {
        colorScheme == .dark
            ? Color(red: 0.90, green: 0.93, blue: 1.0)
            : Color(red: 0.10, green: 0.12, blue: 0.18)
    }
    private var dividerColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.06)
    }
    private var inlineCodeColor: Color {
        colorScheme == .dark
            ? Color(red: 0.88, green: 0.62, blue: 0.42)
            : Color(red: 0.68, green: 0.32, blue: 0.12)
    }

    var body: some View {
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
        case horizontalRule
        case blockquote(text: String)
        case table(headers: [String], rows: [[String]])
        case spacer
    }

    // MARK: - Context-aware spacing

    /// Extra top padding before a block depending on what came before.
    private func topSpacing(for block: MarkdownBlock, prev: MarkdownBlock?) -> CGFloat {
        guard let prev else { return 0 }
        switch block {
        case .heading(let level, _):
            // Big gap before headings, especially h1/h2
            switch prev {
            case .heading: return level == 1 ? 20 : 14
            default: return level == 1 ? 22 : (level == 2 ? 18 : 12)
            }
        case .paragraph:
            switch prev {
            case .heading: return 6
            case .bulletItem, .numberedItem: return 10
            case .codeBlock: return 10
            case .paragraph: return 8
            default: return 6
            }
        case .bulletItem, .numberedItem:
            switch prev {
            case .heading: return 6
            case .paragraph: return 4
            case .bulletItem, .numberedItem: return 0 // tight list
            case .codeBlock: return 8
            default: return 4
            }
        case .codeBlock:
            return 10
        case .horizontalRule:
            return 12
        case .blockquote:
            return 8
        case .table:
            return 10
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
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle()
                    .fill(bulletColor)
                    .frame(width: 5, height: 5)
                    .offset(y: 1)
                inlineMarkdown(text)
            }
            .padding(.leading, 6 + CGFloat(indent) * 20)
            .padding(.top, topPad)
            .padding(.vertical, 2.5)

        case .numberedItem(let number, let text, let indent):
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("\(number).")
                    .font(.system(size: bodyFont, weight: .semibold, design: .rounded))
                    .foregroundStyle(bulletColor)
                    .frame(minWidth: 20, alignment: .trailing)
                inlineMarkdown(text)
            }
            .padding(.leading, CGFloat(indent) * 20)
            .padding(.top, topPad)
            .padding(.vertical, 2.5)

        case .codeBlock(let language, let code):
            codeBlockView(language: language, code: code)
                .padding(.top, topPad)

        case .table(let headers, let rows):
            tableView(headers: headers, rows: rows)
                .padding(.top, topPad)

        case .horizontalRule:
            Rectangle()
                .fill(dividerColor)
                .frame(height: 1)
                .padding(.top, topPad)
                .padding(.bottom, 4)

        case .blockquote(let text):
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(bulletColor.opacity(0.6))
                    .frame(width: 3)
                inlineMarkdown(text)
                    .padding(.leading, 12)
                    .padding(.vertical, 4)
            }
            .padding(.leading, 4)
            .padding(.top, topPad)

        case .spacer:
            Spacer().frame(height: 2)
        }
    }

    // MARK: - Heading

    private func headingView(level: Int, text: String) -> some View {
        let size: CGFloat
        let weight: Font.Weight
        let bottomPad: CGFloat

        switch level {
        case 1:
            size = 20; weight = .bold; bottomPad = 8
        case 2:
            size = 17; weight = .bold; bottomPad = 6
        case 3:
            size = 15; weight = .semibold; bottomPad = 4
        default:
            size = 14; weight = .semibold; bottomPad = 3
        }

        return VStack(alignment: .leading, spacing: bottomPad) {
            inlineMarkdown(text, fontSize: size, fontWeight: weight, color: headingColor)
            if level <= 2 {
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                bulletColor.opacity(level == 1 ? 0.4 : 0.25),
                                dividerColor,
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(height: level == 1 ? 1.5 : 1)
            }
        }
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
            .lineSpacing(lineHeight)
            .textSelection(.enabled)
    }

    // MARK: - Code Block

    private func codeBlockView(language: String, code: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !language.isEmpty {
                HStack {
                    Text(language.lowercased())
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(code, forType: .string)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 9))
                            Text("Copia")
                                .font(.system(size: 9.5, weight: .medium))
                        }
                        .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Copia codice")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    colorScheme == .dark
                        ? Color.white.opacity(0.03)
                        : Color.black.opacity(0.02)
                )

                Rectangle()
                    .fill(codeBorder)
                    .frame(height: 0.5)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.85))
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
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
        // Inline code
        for run in result.runs {
            let range = run.range
            guard let intent = run.inlinePresentationIntent else { continue }
            if intent.contains(.code) {
                result[range].font = .system(
                    size: max(fontSize - 1, 11),
                    weight: .medium,
                    design: .monospaced
                )
                result[range].backgroundColor = NSColor(codeBackground).withAlphaComponent(0.85)
                result[range].foregroundColor = NSColor(inlineCodeColor)
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
            result[lower..<upper].foregroundColor = NSColor.controlAccentColor
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

            // Horizontal rule (not a table separator)
            if (trimmed == "---" || trimmed == "***" || trimmed == "___") && !trimmed.contains("|") {
                flushParagraph()
                blocks.append(.horizontalRule)
                i += 1
                continue
            }

            // Markdown table (pipe-delimited)
            if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") && trimmed.filter({ $0 == "|" }).count >= 2 {
                // Look ahead: next line should be separator (|---|---| etc)
                let nextIdx = i + 1
                if nextIdx < lines.count {
                    let nextTrimmed = lines[nextIdx].trimmingCharacters(in: .whitespaces)
                    let isSeparator = nextTrimmed.hasPrefix("|") && nextTrimmed.contains("-")
                    if isSeparator {
                        flushParagraph()
                        // Parse header
                        let headers = parsePipeRow(trimmed)
                        // Skip header + separator
                        i += 2
                        // Parse data rows
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
                blocks.append(.codeBlock(language: lang, code: codeLines.joined(separator: "\n")))
                continue
            }

            // Blockquote
            if trimmed.hasPrefix("> ") {
                flushParagraph()
                var quoteLines: [String] = []
                while i < lines.count {
                    let l = lines[i].trimmingCharacters(in: .whitespaces)
                    if l.hasPrefix("> ") {
                        quoteLines.append(String(l.dropFirst(2)))
                        i += 1
                    } else if l.hasPrefix(">") {
                        quoteLines.append(String(l.dropFirst(1)))
                        i += 1
                    } else { break }
                }
                blocks.append(.blockquote(text: quoteLines.joined(separator: " ")))
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
            if (trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ")) {
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
            // Header row
            HStack(spacing: 0) {
                ForEach(Array(headers.enumerated()), id: \.offset) { idx, header in
                    Text(header)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(headingColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    if idx < colCount - 1 {
                        Rectangle()
                            .fill(codeBorder)
                            .frame(width: 0.5)
                    }
                }
            }
            .background(
                colorScheme == .dark
                    ? Color(red: 0.95, green: 0.55, blue: 0.18).opacity(0.08)
                    : Color(red: 0.95, green: 0.55, blue: 0.18).opacity(0.06)
            )

            Rectangle().fill(codeBorder).frame(height: 0.5)

            // Data rows
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, row in
                HStack(spacing: 0) {
                    ForEach(0..<colCount, id: \.self) { colIdx in
                        let cellText = colIdx < row.count ? row[colIdx] : ""
                        inlineMarkdown(cellText, fontSize: 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                        if colIdx < colCount - 1 {
                            Rectangle()
                                .fill(codeBorder)
                                .frame(width: 0.5)
                        }
                    }
                }
                .background(
                    rowIdx % 2 == 1
                        ? codeBackground.opacity(0.4)
                        : Color.clear
                )

                if rowIdx < rows.count - 1 {
                    Rectangle().fill(codeBorder).frame(height: 0.5)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(codeBorder, lineWidth: 0.5)
        )
    }

    /// Parse a pipe-delimited row: `| a | b | c |` → `["a", "b", "c"]`
    private func parsePipeRow(_ line: String) -> [String] {
        var text = line.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("|") { text = String(text.dropFirst()) }
        if text.hasSuffix("|") { text = String(text.dropLast()) }
        return text.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    // MARK: - Path Resolver

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
}
