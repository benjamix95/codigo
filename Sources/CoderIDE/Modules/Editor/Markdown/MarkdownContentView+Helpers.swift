import Foundation
import SwiftUI

extension MarkdownContentView {
    // MARK: - File Link Support

    /// File link regex compiled once and reused.
    static let fileLinkRegex: NSRegularExpression? = {
        let pattern =
            #"([A-Za-z0-9_][A-Za-z0-9_./-]*\.(?:swift|m|mm|h|hpp|c|cpp|cc|ts|tsx|js|jsx|py|json|md|markdown|html|css|scss|yaml|yml|xml|plist|strings|kt|kts|java|go|rs|rb|php|sh|zsh|bash|toml|ini|sql)(?::\d+(?::\d+)?)?)\b"#
        return try? NSRegularExpression(pattern: pattern)
    }()

    func resolvePath(_ ref: String) -> String {
        let raw = ref.trimmingCharacters(in: .whitespaces)
        let t = raw.replacingOccurrences(
            of: #":\d+(?::\d+)?$"#,
            with: "",
            options: .regularExpression
        )
        let parts = t.split(separator: "/", omittingEmptySubsequences: false)
        if parts.contains("..") { return t }
        if let context {
            switch ContextPathResolver.resolve(reference: t, context: context) {
            case .resolved(let path): return path
            case .ambiguous(let matches): return matches.first ?? t
            case .notFound: break
            }
        }
        return t
    }

    func buildInlineAttributed(
        _ text: String,
        fontSize: CGFloat,
        fontWeight: Font.Weight,
        color: Color?
    ) -> AttributedString {
        let key = MarkdownInlineAttributedCache.key(
            text: text,
            contextID: context?.id,
            activeFolderPath: context?.activeFolderPath,
            fontSize: fontSize,
            fontWeight: fontWeight,
            codeFontFamily: uiCodeFontFamily,
            codeFontSize: codeFontSize,
            colorSignature: String(describing: color),
            accentSignature: String(describing: accentColor),
            inlineCodeBackgroundSignature: String(describing: inlineCodeBackground),
            inlineCodeColorSignature: String(describing: inlineCodeColor)
        )
        if let cached = MarkdownInlineAttributedCache.get(key) {
            return cached
        }

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
                    result[range].font = FontPreferences.resolveCodeFont(
                        size: max(codeFontSize - 1, 11),
                        family: uiCodeFontFamily,
                        weight: .medium
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

        // File links (regex compiled once as static)
        Self.applyFileReferenceLinks(
            in: &result,
            color: NSColor(accentColor),
            resolver: { resolvePath($0) }
        )
        MarkdownInlineAttributedCache.set(result, for: key)
        return result
    }

    static func applyFileReferenceLinks(
        in attributed: inout AttributedString,
        color: NSColor,
        resolver: (String) -> String
    ) {
        guard let regex = Self.fileLinkRegex else { return }
        let renderedText = String(attributed.characters)
        let nsRenderedText = renderedText as NSString
        let fullRange = NSRange(location: 0, length: nsRenderedText.length)
        for match in regex.matches(in: renderedText, range: fullRange) {
            let fileRef = nsRenderedText.substring(with: match.range)
            if fileRef.hasPrefix("/") || fileRef.contains("..") { continue }
            guard let stringRange = Range(match.range, in: renderedText) else { continue }
            guard let lower = AttributedString.Index(stringRange.lowerBound, within: attributed),
                  let upper = AttributedString.Index(stringRange.upperBound, within: attributed) else {
                continue
            }
            attributed[lower..<upper].foregroundColor = color
            attributed[lower..<upper].underlineStyle = .single
            attributed[lower..<upper].link = URL(fileURLWithPath: resolver(fileRef))
        }
    }

    // MARK: - Assistant display layout normalization

    static func normalizeAssistantDisplayLayout(_ input: String) -> String {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return trimmedInput }

        let parts = splitByCodeFence(trimmedInput)
        let normalized = parts.map { part -> String in
            guard !part.isCodeFence else { return part.text }
            var segment = normalizePlainMarkdownSegment(part.text)
            segment = enforceConsistentSpacing(segment)
            return segment
        }.joined()

        return normalized
            .replacingOccurrences(of: "\n\n\n+", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Enforce consistent spacing: blank line before headings, between paragraphs,
    /// and after list blocks. This normalizes output from all LLMs to the same visual layout.
    static func enforceConsistentSpacing(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var result: [String] = []
        for (i, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let prev = i > 0 ? lines[i - 1].trimmingCharacters(in: .whitespaces) : ""
            if trimmed.hasPrefix("#") && !prev.isEmpty {
                if !(result.last?.trimmingCharacters(in: .whitespaces).isEmpty ?? false) {
                    result.append("")
                }
            }
            let prevIsList = prev.hasPrefix("- ") || prev.hasPrefix("* ") || prev.hasPrefix("+ ")
                || numberedLineRegex.firstMatch(in: prev, options: [], range: NSRange(location: 0, length: (prev as NSString).length)) != nil
            let currentIsList = trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ")
                || numberedLineRegex.firstMatch(in: trimmed, options: [], range: NSRange(location: 0, length: (trimmed as NSString).length)) != nil
            if prevIsList && !currentIsList && !trimmed.isEmpty && !trimmed.hasPrefix("#") {
                if !(result.last?.trimmingCharacters(in: .whitespaces).isEmpty ?? false) {
                    result.append("")
                }
            }
            if !prevIsList && currentIsList && !prev.isEmpty && !prev.hasPrefix("#") {
                if !(result.last?.trimmingCharacters(in: .whitespaces).isEmpty ?? false) {
                    result.append("")
                }
            }
            result.append(line)
        }
        return result.joined(separator: "\n")
    }

    static func splitByCodeFence(_ input: String) -> [(text: String, isCodeFence: Bool)] {
        var segments: [(String, Bool)] = []
        var cursor = input.startIndex

        while cursor < input.endIndex {
            guard let fenceRange = input[cursor...].range(of: "```") else {
                let rest = String(input[cursor...])
                if !rest.isEmpty {
                    segments.append((rest, false))
                }
                break
            }

            let before = String(input[cursor..<fenceRange.lowerBound])
            if !before.isEmpty {
                segments.append((before, false))
            }

            if let nextFence = input[fenceRange.upperBound...].range(of: "```") {
                let fenceChunk = String(input[fenceRange.lowerBound..<nextFence.upperBound])
                segments.append((fenceChunk, true))
                cursor = nextFence.upperBound
            } else {
                let remainder = String(input[fenceRange.lowerBound...])
                segments.append((remainder, true))
                break
            }
        }

        return segments
    }

    static func normalizePlainMarkdownSegment(_ segment: String) -> String {
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

    static let sentenceSplitRegex = try! NSRegularExpression(
        pattern: #"(?<=[.!?])\s+(?=[A-ZÀ-ÖØ-Ý0-9])"#, options: [])

    static func normalizeDenseLine(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return line }

        // Keep already-structured markdown lines untouched.
        if isStructuredMarkdownLine(trimmed) {
            return line
        }

        guard !trimmed.contains("\n"), trimmed.count > 320 else {
            return line
        }

        let regex = sentenceSplitRegex
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

    static let numberedLineRegex = try! NSRegularExpression(pattern: #"^\d+\.\s+"#, options: [])

    static func isStructuredMarkdownLine(_ line: String) -> Bool {
        if line.hasPrefix("#") || line.hasPrefix(">") { return true }
        if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("+ ") { return true }
        if line.hasPrefix("|"), line.hasSuffix("|") { return true }
        if line == "---" || line == "***" || line == "___" { return true }

        let ns = line as NSString
        let range = NSRange(location: 0, length: ns.length)
        return numberedLineRegex.firstMatch(in: line, options: [], range: range) != nil
    }
}
