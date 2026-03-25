import SwiftUI

extension MarkdownContentView {
    // MARK: - Body

    /// Whether the current content contains block-level markdown that
    /// requires the full parser (headings, fenced code, lists, tables).
    private var hasBlockLevelMarkdown: Bool {
        let text = displayContent
        // Quick scan — avoid full parsing when content is plain inline text.
        if text.contains("```") { return true }
        let lines = text.components(separatedBy: "\n")
        for line in lines.prefix(200) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") || trimmed.hasPrefix("## ")
                || trimmed.hasPrefix("### ") || trimmed.hasPrefix("#### ") { return true }
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") { return true }
            if let dot = trimmed.firstIndex(of: "."), dot > trimmed.startIndex,
               trimmed[trimmed.startIndex..<dot].allSatisfy(\.isNumber),
               dot < trimmed.index(before: trimmed.endIndex),
               trimmed[trimmed.index(after: dot)] == " " { return true }
            if trimmed.hasPrefix("> ") { return true }
            if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") { return true }
        }
        return false
    }

    @ViewBuilder
    var contentBody: some View {
        if isStreaming && !hasBlockLevelMarkdown {
            let _ = ChatRenderLogger.logRender(
                "Markdown.streamingInline",
                detail: "len=\(content.count)"
            )
            // Fast path: inline-only content during streaming.
            streamingBody
        } else if isStreaming {
            let _ = ChatRenderLogger.logRender(
                "Markdown.streamingFull",
                detail: "len=\(content.count) blocks=\(cachedBlocks?.count ?? -1)"
            )
            // Streaming with block-level markdown: use full parser
            // so headings, code blocks, lists render in real time.
            streamingFullMarkdownBody
        } else {
            fullMarkdownBody
        }
    }

    // MARK: - Streaming Body (fast, no block parsing)

    var streamingBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            let text = displayContent
            if text.isEmpty {
                StreamingCursorView()
            } else {
                (Text(buildStreamingAttributed(text))
                    + Text(" \u{258C}")
                    .font(FontPreferences.resolveSansFont(size: bodyFont, family: uiSansFontFamily))
                    .foregroundColor(textPrimary.opacity(0.45)))
                .font(FontPreferences.resolveSansFont(size: bodyFont, family: uiSansFontFamily))
                .foregroundStyle(textPrimary)
                .lineSpacing(bodyLineSpacing)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Thread-local cache for the last streaming attributed string.
    /// During streaming, text grows incrementally (append-only). We cache
    /// the last result keyed by text length — if the length hasn't changed,
    /// the content hasn't changed and we skip the expensive
    /// `AttributedString(markdown:)` parse + run iteration.
    private static var lastStreamingAttributedLength: Int = 0
    private static var lastStreamingAttributedResult: AttributedString?

    fileprivate func buildStreamingAttributed(_ text: String) -> AttributedString {
        let length = text.utf16.count
        if length == Self.lastStreamingAttributedLength,
           let cached = Self.lastStreamingAttributedResult {
            return cached
        }

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
                result[range].font = FontPreferences.resolveCodeFont(
                    size: max(codeFontSize - 1, 11),
                    family: uiCodeFontFamily,
                    weight: .medium
                )
                result[range].backgroundColor = NSColor(inlineCodeBackground)
                result[range].foregroundColor = NSColor(inlineCodeColor)
            }
        }
        Self.lastStreamingAttributedLength = length
        Self.lastStreamingAttributedResult = result
        return result
    }

    // MARK: - Streaming Full Markdown Body

    /// Block-level rendering during streaming. Uses the same parser as
    /// `fullMarkdownBody` but appends a blinking cursor after the last block.
    var streamingFullMarkdownBody: some View {
        let blocks = cachedBlocks ?? parseBlocks()
        return VStack(alignment: .leading, spacing: 0) {
            if blocks.isEmpty {
                StreamingCursorView()
            } else {
                ForEach(Array(blocks.enumerated()), id: \.offset) { idx, block in
                    blockView(for: block, prevBlock: idx > 0 ? blocks[idx - 1] : nil)
                }
                // Streaming cursor after the last block
                HStack(spacing: 0) {
                    Text(" \u{258C}")
                        .font(FontPreferences.resolveSansFont(size: bodyFont, family: uiSansFontFamily))
                        .foregroundColor(textPrimary.opacity(0.45))
                    Spacer()
                }
            }
        }
        .frame(maxWidth: fillWidth ? .infinity : nil, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            if cachedBlocks == nil { cachedBlocks = parseBlocks() }
        }
        .onChange(of: content) { _ in
            cachedBlocks = parseBlocks()
        }
    }

    // MARK: - Full Markdown Body (block-level)

    var fullMarkdownBody: some View {
        let blocks = cachedBlocks ?? parseBlocks()
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { idx, block in
                blockView(for: block, prevBlock: idx > 0 ? blocks[idx - 1] : nil)
            }
        }
        .frame(maxWidth: fillWidth ? .infinity : nil, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            if cachedBlocks == nil { cachedBlocks = parseBlocks() }
        }
        .onChange(of: content) { _ in
            cachedBlocks = parseBlocks()
        }
    }

    // MARK: - Context-Aware Spacing

    func topSpacing(for block: MarkdownBlock, prev: MarkdownBlock?) -> CGFloat {
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
    func blockView(for block: MarkdownBlock, prevBlock: MarkdownBlock?) -> some View {
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

}
