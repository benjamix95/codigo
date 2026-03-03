import Foundation

extension EventNormalizer {
    static func parseInstantGrep(payload: [String: String], timestamp: Date) -> InstantGrepResult? {
        guard let query = payload["query"], !query.isEmpty else { return nil }
        let scope = payload["pathScope"] ?? payload["scope"] ?? "."
        let durationMs = Int(payload["duration_ms"] ?? "")
        let preview = payload["previewLines"] ?? ""
        let parsedMatches = parseMatchLines(from: preview)

        return InstantGrepResult(
            query: query,
            scope: scope,
            // Mantiene coerenza tra numero mostrato e match effettivamente disponibili.
            matchesCount: parsedMatches.count,
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
            // Salta i marcatori di file binari da grep/rg e righe con byte NUL
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            let loweredLine = trimmedLine.lowercased()
            if loweredLine.hasPrefix("binary file")
                || loweredLine.contains("binary file matches")
                || trimmedLine.contains("\0")
            {
                continue
            }

            let parts = line.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3 else { continue }
            let file = String(parts[0])
            // Salta percorsi file vuoti
            guard !file.isEmpty else { continue }
            // Il numero di riga deve essere positivo (> 0)
            guard let number = Int(parts[1]), number > 0 else { continue }
            let rawPreview = String(parts[2]).trimmingCharacters(in: .whitespaces)
            // Tronca l'anteprima a 500 caratteri per evitare consumo eccessivo di memoria
            let preview = rawPreview.count > 500 ? String(rawPreview.prefix(500)) : rawPreview
            matches.append(InstantGrepMatch(file: file, line: number, preview: preview))
        }
        return matches
    }

    static func parseSearchQueryFromCommand(_ command: String) -> String? {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let args = tokenizeShellArguments(trimmed)
        guard !args.isEmpty else { return nil }

        // Ricerca case-insensitive del comando: supporta rg/grep in qualunque casing.
        guard let cmdIndex = args.firstIndex(where: {
            $0.caseInsensitiveCompare("rg") == .orderedSame
                || $0.caseInsensitiveCompare("grep") == .orderedSame
        }) else {
            return nil
        }

        let valueTakingFlags: Set<String> = [
            "-g", "--glob", "-t", "--type", "-m", "--max-count",
            "-A", "-B", "-C", "-f", "--file", "-j", "--threads",
        ]
        let queryFlags: Set<String> = ["-e", "--regexp"]

        var index = cmdIndex + 1
        while index < args.count {
            let token = args[index]

            if token == "--" {
                index += 1
                break
            }

            if token.hasPrefix("-") {
                if let eqIndex = token.firstIndex(of: "=") {
                    let flag = String(token[..<eqIndex]).lowercased()
                    let value = String(token[token.index(after: eqIndex)...])
                    if queryFlags.contains(flag) {
                        return value.isEmpty ? nil : value
                    }
                    index += 1
                    continue
                }

                let normalized = token.lowercased()
                if normalized.hasPrefix("-e"), normalized != "-e" {
                    let attached = String(token.dropFirst(2))
                    if !attached.isEmpty { return attached }
                }

                if queryFlags.contains(normalized) {
                    let valueIndex = index + 1
                    guard valueIndex < args.count else { return nil }
                    return args[valueIndex]
                }

                if valueTakingFlags.contains(normalized) {
                    index += 2
                    continue
                }

                index += 1
                continue
            }

            // Primo argomento non-flag: query pattern standard di rg/grep.
            return token
        }

        if index < args.count {
            return args[index]
        }
        return nil
    }

    private static func tokenizeShellArguments(_ input: String) -> [String] {
        var args: [String] = []
        var current = ""
        var inSingleQuote = false
        var inDoubleQuote = false
        var escaping = false

        for char in input {
            if escaping {
                current.append(char)
                escaping = false
                continue
            }

            if char == "\\" && !inSingleQuote {
                escaping = true
                continue
            }

            if char == "'" && !inDoubleQuote {
                inSingleQuote.toggle()
                continue
            }

            if char == "\"" && !inSingleQuote {
                inDoubleQuote.toggle()
                continue
            }

            if char.isWhitespace && !inSingleQuote && !inDoubleQuote {
                if !current.isEmpty {
                    args.append(current)
                    current.removeAll(keepingCapacity: true)
                }
                continue
            }

            current.append(char)
        }

        if !current.isEmpty {
            args.append(current)
        }
        return args
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
