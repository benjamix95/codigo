import Foundation

// MARK: - Merge Conflict Parser

/// Parsa i marker di conflitto Git (`<<<<<<<`, `=======`, `>>>>>>>`) da un file.
enum MergeConflictParser {
    /// Un singolo conflitto trovato nel file.
    struct ConflictHunk: Identifiable, Sendable {
        let id: UUID
        let startLine: Int
        let separatorLine: Int
        let endLine: Int
        let oursContent: String
        let theirsContent: String
        let oursLabel: String
        let theirsLabel: String

        init(startLine: Int, separatorLine: Int, endLine: Int,
             oursContent: String, theirsContent: String,
             oursLabel: String = "HEAD", theirsLabel: String = "") {
            self.id = UUID()
            self.startLine = startLine
            self.separatorLine = separatorLine
            self.endLine = endLine
            self.oursContent = oursContent
            self.theirsContent = theirsContent
            self.oursLabel = oursLabel
            self.theirsLabel = theirsLabel
        }
    }

    /// Risultato del parsing di un file con conflitti.
    struct ParseResult: Sendable {
        let filePath: String
        let hunks: [ConflictHunk]
        let hasConflicts: Bool
        let fullContent: String
    }

    /// Parsa un file e restituisce i conflitti trovati.
    static func parse(filePath: String) -> ParseResult {
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            return ParseResult(filePath: filePath, hunks: [], hasConflicts: false, fullContent: "")
        }
        return parse(content: content, filePath: filePath)
    }

    /// Parsa il contenuto di un file per trovare conflitti.
    static func parse(content: String, filePath: String) -> ParseResult {
        let lines = content.components(separatedBy: .newlines)
        var hunks: [ConflictHunk] = []

        var i = 0
        while i < lines.count {
            if lines[i].hasPrefix("<<<<<<<") {
                if let hunk = parseHunk(lines: lines, startIndex: i) {
                    hunks.append(hunk)
                    i = hunk.endLine
                }
            }
            i += 1
        }

        return ParseResult(
            filePath: filePath,
            hunks: hunks,
            hasConflicts: !hunks.isEmpty,
            fullContent: content
        )
    }

    /// Risolve un singolo conflitto nel contenuto del file.
    static func resolveHunk(
        content: String,
        hunk: ConflictHunk,
        resolution: ConflictResolution
    ) -> String {
        let lines = content.components(separatedBy: .newlines)
        var result: [String] = []
        var i = 0

        while i < lines.count {
            if i + 1 == hunk.startLine {
                // Inserisci la risoluzione
                switch resolution {
                case .ours:
                    result.append(hunk.oursContent)
                case .theirs:
                    result.append(hunk.theirsContent)
                case .both:
                    result.append(hunk.oursContent)
                    result.append(hunk.theirsContent)
                case .manual(let text):
                    result.append(text)
                }
                // `endLine` è 1-based: allineiamo all'indice 0-based prima dell'incremento finale.
                i = hunk.endLine - 1
            } else {
                result.append(lines[i])
            }
            i += 1
        }

        return result.joined(separator: "\n")
    }

    // MARK: - Private

    private static func parseHunk(lines: [String], startIndex: Int) -> ConflictHunk? {
        let oursLabel = extractLabel(from: lines[startIndex], prefix: "<<<<<<<")
        var separatorIndex: Int?
        var endIndex: Int?
        var oursLines: [String] = []
        var theirsLines: [String] = []

        for j in (startIndex + 1)..<lines.count {
            if lines[j].hasPrefix("=======") {
                separatorIndex = j
            } else if lines[j].hasPrefix(">>>>>>>") {
                endIndex = j
                break
            } else if separatorIndex == nil {
                oursLines.append(lines[j])
            } else {
                theirsLines.append(lines[j])
            }
        }

        guard let sep = separatorIndex, let end = endIndex else { return nil }
        let theirsLabel = extractLabel(from: lines[end], prefix: ">>>>>>>")

        return ConflictHunk(
            startLine: startIndex + 1,
            separatorLine: sep + 1,
            endLine: end + 1,
            oursContent: oursLines.joined(separator: "\n"),
            theirsContent: theirsLines.joined(separator: "\n"),
            oursLabel: oursLabel,
            theirsLabel: theirsLabel
        )
    }

    private static func extractLabel(from line: String, prefix: String) -> String {
        line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
    }
}

/// Tipo di risoluzione per un conflitto.
enum ConflictResolution: Sendable {
    case ours
    case theirs
    case both
    case manual(String)
}
