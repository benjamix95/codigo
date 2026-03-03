import Foundation

extension EventNormalizer {
    static func parseInstantGrep(payload: [String: String], timestamp: Date) -> InstantGrepResult? {
        guard let query = payload["query"], !query.isEmpty else { return nil }
        let scope = payload["pathScope"] ?? payload["scope"] ?? "."
        let matchesCount = Int(payload["matchesCount"] ?? "") ?? 0
        let durationMs = Int(payload["duration_ms"] ?? "")
        let preview = payload["previewLines"] ?? ""
        let parsedMatches = parseMatchLines(from: preview)

        return InstantGrepResult(
            query: query,
            scope: scope,
            matchesCount: max(matchesCount, parsedMatches.count),
            durationMs: durationMs,
            matches: parsedMatches,
            createdAt: timestamp
        )
    }

    static func parseInstantGrepFromCommand(payload: [String: String], timestamp: Date) -> InstantGrepResult? {
        guard let command = payload["command"] else { return nil }
        let lowered = command.lowercased()
        let hasRG = lowered.hasPrefix("rg ") || lowered.contains(" rg ")
        let hasGrep = lowered.hasPrefix("grep ") || lowered.contains(" grep ")
        guard hasRG || hasGrep else { return nil }

        let query = parseSearchQueryFromCommand(command) ?? "(query)"
        let scope = payload["cwd"] ?? "."
        let output = payload["output"] ?? ""
        let matches = parseMatchLines(from: output)
        guard !matches.isEmpty else { return nil }

        return InstantGrepResult(
            query: query,
            scope: scope,
            matchesCount: matches.count,
            durationMs: nil,
            matches: Array(matches.prefix(30)),
            createdAt: timestamp
        )
    }

    static func parseReadActivityFromCommand(payload: [String: String], timestamp: Date) -> TaskActivity? {
        guard let command = payload["command"] else { return nil }
        let lower = command.lowercased()
        guard lower.contains("cat ")
            || lower.contains("sed -n")
            || lower.contains("head ")
            || lower.contains("tail ")
        else { return nil }

        guard let path = extractReadPath(from: command), !path.isEmpty else { return nil }
        let title = "Read • \((path as NSString).lastPathComponent)"

        return TaskActivity(
            type: "read_batch_completed",
            title: title,
            detail: path,
            payload: [
                "title": title,
                "detail": path,
                "path": path,
                "file": path,
                "count": "1",
                "files": path,
                "status": "completed",
                "source": "synthetic_command_read",
            ],
            timestamp: timestamp,
            phase: .editing,
            isRunning: false
        )
    }

    static func parseMatchLines(from output: String) -> [InstantGrepMatch] {
        let lines = output.split(separator: "\n").map(String.init)
        var matches: [InstantGrepMatch] = []

        for line in lines.prefix(200) {
            let parts = line.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3 else { continue }
            let file = String(parts[0])
            guard let number = Int(parts[1]) else { continue }
            let preview = String(parts[2]).trimmingCharacters(in: .whitespaces)
            matches.append(InstantGrepMatch(file: file, line: number, preview: preview))
        }
        return matches
    }

    static func parseSearchQueryFromCommand(_ command: String) -> String? {
        let tokens = command.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return nil }
        if let rgIndex = tokens.firstIndex(where: { $0 == "rg" || $0.hasSuffix("/rg") || $0 == "grep" || $0.hasSuffix("/grep") }) {
            for token in tokens.dropFirst(rgIndex + 1) {
                if token.hasPrefix("-") { continue }
                return token.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            }
        }
        return nil
    }

    static func extractReadPath(from command: String) -> String? {
        let patterns = [
            #"(?:^|\s)(?:cat|head|tail)\s+(?:-[^\s]+\s+)*(?:['"]?([^'" \t\n]+)['"]?)"#,
            #"(?:^|\s)sed\s+-n\s+['"][^'\"]+['"]\s+['"]?([^'" \t\n]+)['"]?"#,
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let ns = command as NSString
            let range = NSRange(location: 0, length: ns.length)

            if let match = regex.firstMatch(in: command, options: [], range: range),
               match.numberOfRanges > 1
            {
                let valueRange = match.range(at: 1)
                if valueRange.location != NSNotFound {
                    let value = ns.substring(with: valueRange)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !value.isEmpty {
                        return value
                    }
                }
            }
        }
        return nil
    }
}
