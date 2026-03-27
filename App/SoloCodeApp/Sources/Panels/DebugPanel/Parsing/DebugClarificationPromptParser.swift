import Foundation

/// Estrae testo introduttivo e opzioni stile (a)/(b) o `a)` da prompt `debug_request_user` / testo libero.
enum DebugClarificationPromptParser {
    struct Parsed: Equatable {
        var preamble: String
        var options: [Option]

        struct Option: Identifiable, Equatable {
            let id: String
            let letter: String
            let text: String
        }
    }

    private static let patterns: [(NSRegularExpression, Int, Int)] = {
        let specs: [(String, Int, Int)] = [
            (#"^\(([A-Za-z])\)\s+(.+)$"#, 1, 2),
            (#"^([A-Za-z])[.)]\s+(.+)$"#, 1, 2),
            (#"^\s*[-*•]\s+\(?([A-Za-z])\)?[.)]\s+(.+)$"#, 1, 2),
            (#"^\s*[-*•]\s+\(([A-Za-z])\)\s+(.+)$"#, 1, 2),
        ]
        return specs.compactMap { pattern, g1, g2 in
            guard let rx = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
            return (rx, g1, g2)
        }
    }()

    private static let inlineOptionMarker: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"(?i)(?:^|[\s;])\(?([A-Za-z])\)?[.)]\s+"#,
        options: []
    )

    static func parse(_ raw: String) -> Parsed {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return Parsed(preamble: "", options: [])
        }
        let lines = normalized.components(separatedBy: .newlines)
        let hits = extractLineHits(from: lines)

        if hits.count >= 2 {
            return buildParsedFromLineHits(hits, lines: lines)
        }

        if let inlineParsed = parseInlineOptions(from: normalized) {
            return inlineParsed
        }

        return Parsed(preamble: normalized, options: [])
    }

    private static func extractLineHits(
        from lines: [String]
    ) -> [(lineIndex: Int, letter: String, body: String)] {
        var hits: [(lineIndex: Int, letter: String, body: String)] = []
        for (idx, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            for (rx, gLetter, gBody) in patterns {
                let range = NSRange(trimmed.startIndex..., in: trimmed)
                guard let m = rx.firstMatch(in: trimmed, range: range),
                      let lr = Range(m.range(at: gLetter), in: trimmed),
                      let br = Range(m.range(at: gBody), in: trimmed)
                else { continue }
                let letter = String(trimmed[lr]).lowercased()
                let body = String(trimmed[br]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !letter.isEmpty, !body.isEmpty else { continue }
                hits.append((idx, letter, body))
                break
            }
        }
        return hits
    }

    private static func buildParsedFromLineHits(
        _ hits: [(lineIndex: Int, letter: String, body: String)],
        lines: [String]
    ) -> Parsed {
        let firstIdx = hits[0].lineIndex
        let preamble: String
        if firstIdx == 0 {
            preamble = ""
        } else {
            preamble = lines[0..<firstIdx]
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return Parsed(preamble: preamble, options: deduplicatedOptions(from: hits))
    }

    private static func parseInlineOptions(from normalized: String) -> Parsed? {
        guard let inlineOptionMarker else { return nil }
        let range = NSRange(normalized.startIndex..., in: normalized)
        let matches = inlineOptionMarker.matches(in: normalized, range: range)
        guard matches.count >= 2 else { return nil }

        let firstMatchLocation = matches[0].range.location
        guard let firstMarkerRange = Range(NSRange(location: firstMatchLocation, length: 0), in: normalized) else {
            return nil
        }
        let preamble = normalized[..<firstMarkerRange.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var hits: [(lineIndex: Int, letter: String, body: String)] = []
        for (index, match) in matches.enumerated() {
            guard let letterRange = Range(match.range(at: 1), in: normalized) else { continue }
            let bodyStart = normalized.index(normalized.startIndex, offsetBy: match.range.location + match.range.length)
            let bodyEnd: String.Index = {
                if index + 1 < matches.count {
                    return normalized.index(normalized.startIndex, offsetBy: matches[index + 1].range.location)
                }
                return normalized.endIndex
            }()
            let body = normalized[bodyStart..<bodyEnd]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let letter = String(normalized[letterRange]).lowercased()
            guard !letter.isEmpty, !body.isEmpty else { continue }
            hits.append((lineIndex: index, letter: letter, body: body))
        }

        guard hits.count >= 2 else { return nil }
        return Parsed(preamble: preamble, options: deduplicatedOptions(from: hits))
    }

    private static func deduplicatedOptions(
        from hits: [(lineIndex: Int, letter: String, body: String)]
    ) -> [Parsed.Option] {
        var seen = Set<String>()
        var options: [Parsed.Option] = []
        for hit in hits {
            guard !seen.contains(hit.letter) else { continue }
            seen.insert(hit.letter)
            options.append(
                Parsed.Option(
                    id: hit.letter,
                    letter: hit.letter,
                    text: hit.body
                )
            )
        }
        return options
    }
}
