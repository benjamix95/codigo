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
        // Handle quoted multi-word patterns like: rg "hello world" Sources/
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Find the rg/grep command position
        guard let cmdRange = trimmed.range(of: #"(?:^|\s)(?:rg|grep)(?:\s|$)"#, options: .regularExpression) else {
            return nil
        }
        let afterCmd = String(trimmed[cmdRange.upperBound...]).trimmingCharacters(in: .whitespaces)

        // Skip flags, then extract the first non-flag argument (possibly quoted)
        var remaining = afterCmd[afterCmd.startIndex...]
        while !remaining.isEmpty {
            remaining = remaining.drop(while: \.isWhitespace)
            guard !remaining.isEmpty else { break }

            if remaining.hasPrefix("-") {
                // Skip flag and its value if it's a known value-taking flag
                let flag = remaining.prefix(while: { !$0.isWhitespace })
                remaining = remaining.dropFirst(flag.count).drop(while: \.isWhitespace)
                // Flags like -t, -g, --type, --glob take a value argument
                let flagStr = String(flag)
                let valueTakingFlags = ["-t", "-g", "--type", "--glob", "--max-count", "-m", "-C", "-A", "-B", "--threads", "-j"]
                if valueTakingFlags.contains(where: { flagStr == $0 || flagStr.hasPrefix($0 + "=") }) && !flagStr.contains("=") {
                    let val = remaining.prefix(while: { !$0.isWhitespace })
                    remaining = remaining.dropFirst(val.count)
                }
                continue
            }

            // Found the pattern argument — handle quoted strings
            if remaining.hasPrefix("\"") || remaining.hasPrefix("'") {
                let quote = remaining.first!
                remaining = remaining.dropFirst()
                if let endIdx = remaining.firstIndex(of: quote) {
                    return String(remaining[remaining.startIndex..<endIdx])
                }
                return String(remaining) // Unterminated quote, return what we have
            }

            // Unquoted argument
            let arg = remaining.prefix(while: { !$0.isWhitespace })
            return String(arg)
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
