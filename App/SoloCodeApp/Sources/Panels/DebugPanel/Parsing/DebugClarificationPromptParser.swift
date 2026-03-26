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

    static func parse(_ raw: String) -> Parsed {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return Parsed(preamble: "", options: [])
        }
        let lines = normalized.components(separatedBy: .newlines)
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

        guard hits.count >= 2 else {
            return Parsed(preamble: normalized, options: [])
        }

        let firstIdx = hits[0].lineIndex
        let preamble: String
        if firstIdx == 0 {
            preamble = ""
        } else {
            preamble = lines[0..<firstIdx]
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

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

        return Parsed(preamble: preamble, options: options)
    }
}
