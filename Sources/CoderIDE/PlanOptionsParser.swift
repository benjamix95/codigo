import Foundation

/// Opzione estratta da un piano AI
struct PlanOption: Identifiable, Equatable {
    let id: Int
    let title: String
    let fullText: String
}

/// Estrae opzioni numerate da un testo di piano (es. "## Opzione 1: ...", "Opzione 2:", ecc.)
enum PlanOptionsParser {

    /// Restituisce le opzioni parsegate o una singola opzione con l'intero testo se il parsing fallisce
    static func parse(from text: String) -> [PlanOption] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var options: [(num: Int, title: String, full: String)] = []
        let lines = trimmed.components(separatedBy: .newlines)

        var i = 0
        while i < lines.count {
            let line = lines[i]
            // Match "Opzione 1:" o "## Opzione 1: Title"
            if line.range(of: #"Opzione\s+\d+\s*[:\-]"#, options: .regularExpression) != nil {
                var num = 0
                var title = "Opzione"
                if let regex = try? NSRegularExpression(pattern: #"Opzione\s+(\d+)\s*[:\-]\s*(.*)"#),
                   let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {
                    if let r1 = Range(match.range(at: 1), in: line), let n = Int(line[r1]) {
                        num = n
                    }
                    if match.range(at: 2).location != NSNotFound, let r2 = Range(match.range(at: 2), in: line) {
                        title = String(line[r2]).trimmingCharacters(in: .whitespaces)
                        if title.isEmpty { title = "Opzione \(num)" }
                    } else {
                        title = "Opzione \(num)"
                    }
                }

                var fullLines = [line]
                i += 1
                while i < lines.count {
                    let next = lines[i]
                    if next.range(of: #"^\s*(?:##\s*)?Opzione\s+\d+"#, options: .regularExpression) != nil {
                        break
                    }
                    fullLines.append(next)
                    i += 1
                }
                let fullText = fullLines.joined(separator: "\n")
                options.append((num, title, fullText))
                continue
            }
            i += 1
        }

        if !options.isEmpty {
            return options.sorted(by: { $0.num < $1.num }).map {
                PlanOption(id: $0.num, title: $0.title, fullText: $0.full)
            }
        }

        // Fallback: blocchi numerati "1. ..." o "1) ..." con contenuto lungo
        let paragraphs = trimmed.components(separatedBy: "\n\n")
        for para in paragraphs {
            let p = para.trimmingCharacters(in: .whitespaces)
            guard p.count >= 20 else { continue }
            if let regex = try? NSRegularExpression(pattern: #"^(\d+)[.)]\s*(.+)"#),
               let match = regex.firstMatch(in: p, range: NSRange(p.startIndex..., in: p)),
               let r1 = Range(match.range(at: 1), in: p), let num = Int(p[r1]),
               num >= 1, num <= 20 {
                let content: String
                if match.range(at: 2).location != NSNotFound, let r2 = Range(match.range(at: 2), in: p) {
                    content = String(p[r2])
                } else {
                    content = p
                }
                let title = String(content.prefix(80))
                options.append((num, title, p))
            }
        }

        if !options.isEmpty {
            return options.sorted(by: { $0.num < $1.num }).map {
                PlanOption(id: $0.num, title: $0.title, fullText: $0.full)
            }
        }

        // Ultimo fallback: intero testo come unica opzione
        return [PlanOption(id: 1, title: "Piano completo", fullText: trimmed)]
    }
}
