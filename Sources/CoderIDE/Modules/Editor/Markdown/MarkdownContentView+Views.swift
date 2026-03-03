import SwiftUI

extension MarkdownContentView {
    // MARK: - Body

    @ViewBuilder
    var contentBody: some View {
        if isStreaming {
            streamingBody
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

    fileprivate func buildStreamingAttributed(_ text: String) -> AttributedString {
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
        return result
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
        .onChange(of: content) { _, _ in
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

    // MARK: - Headings

    func headingView(level: Int, text: String) -> some View {
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

    func bulletItemView(text: String, indent: Int) -> some View {
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

    func numberedItemView(number: String, text: String, indent: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(number).")
                .font(FontPreferences.resolveSansFont(
                    size: bodyFont,
                    family: uiSansFontFamily,
                    weight: .bold,
                    design: .rounded
                ))
                .foregroundStyle(accentColor.opacity(0.8))
                .frame(minWidth: 22, alignment: .trailing)
            inlineMarkdown(text)
        }
        .padding(.leading, CGFloat(indent) * 22)
        .padding(.vertical, 4)
    }

    // MARK: - Horizontal Rule

    var horizontalRuleView: some View {
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

    func blockquoteView(text: String) -> some View {
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
    func inlineMarkdown(
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
            .font(FontPreferences.resolveSansFont(size: sz, family: uiSansFontFamily, weight: fontWeight))
            .foregroundStyle(color ?? textPrimary)
            .lineSpacing(bodyLineSpacing)
            .textSelection(.enabled)
    }

    // MARK: - Code Block

    func codeBlockView(language: String, code: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar
            HStack {
                if !language.isEmpty {
                    Text(language.lowercased())
                        .font(FontPreferences.resolveCodeFont(size: max(codeFontSize - 2, 10), family: uiCodeFontFamily, weight: .bold))
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
                            .font(FontPreferences.resolveSansFont(size: 9, family: uiSansFontFamily))
                        Text("Copy")
                            .font(FontPreferences.resolveSansFont(size: 9.5, family: uiSansFontFamily, weight: .medium))
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
                    .font(FontPreferences.resolveCodeFont(size: codeFontSize, family: uiCodeFontFamily))
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

    func mermaidBlockView(code: String) -> some View {
        MermaidDiagramView(
            mermaidCode: code,
            accentColor: accentColor
        )
    }

    // MARK: - Table Rendering

    func tableView(headers: [String], rows: [[String]]) -> some View {
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
}
