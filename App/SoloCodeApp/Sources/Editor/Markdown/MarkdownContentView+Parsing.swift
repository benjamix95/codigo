import Foundation

extension MarkdownContentView {
    // MARK: - Block Parser

    func parseBlocks() -> [MarkdownBlock] {
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
                    let headers = parsePipeRow(trimmed)
                    let isSeparator = isPipeTableSeparator(nextTrimmed, expectedColumnCount: headers.count)
                    if isSeparator {
                        flushParagraph()
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
                let fencePayload = String(trimmed.dropFirst(3))
                let lang = fencePayload.trimmingCharacters(in: .whitespaces)

                // Support inline fenced blocks, e.g. ```mermaid graph TD; A-->B```
                if let closingRange = fencePayload.range(of: "```") {
                    let inlinePayload = String(fencePayload[..<closingRange.lowerBound])
                        .trimmingCharacters(in: .whitespaces)
                    if inlinePayload.lowercased().hasPrefix("mermaid") {
                        let code = String(inlinePayload.dropFirst("mermaid".count))
                            .trimmingCharacters(in: .whitespaces)
                        blocks.append(.mermaid(code: code))
                    } else {
                        let parts = inlinePayload.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
                        let inlineLanguage = parts.first.map(String.init) ?? ""
                        let inlineCode = parts.count > 1 ? String(parts[1]) : ""
                        blocks.append(.codeBlock(language: inlineLanguage, code: inlineCode))
                    }
                    i += 1
                    continue
                }

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
               let num = Int(trimmed[trimmed.startIndex..<dotIdx]) {
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

#if DEBUG
    func parseBlocksForTests() -> [MarkdownBlock] {
        parseBlocks()
    }
#endif

    func parsePipeRow(_ line: String) -> [String] {
        var text = line.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("|") { text = String(text.dropFirst()) }
        if text.hasSuffix("|") { text = String(text.dropLast()) }
        return text.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    func isPipeTableSeparator(_ line: String, expectedColumnCount: Int) -> Bool {
        guard line.hasPrefix("|"), line.hasSuffix("|") else { return false }
        let cells = parsePipeRow(line)
        guard !cells.isEmpty, cells.count == expectedColumnCount else { return false }
        return cells.allSatisfy(isPipeSeparatorCell)
    }

    func isPipeSeparatorCell(_ rawCell: String) -> Bool {
        let cell = rawCell.trimmingCharacters(in: .whitespaces)
        guard !cell.isEmpty else { return false }
        return cell.range(of: #"^:?-{3,}:?$"#, options: .regularExpression) != nil
    }
}
