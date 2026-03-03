import Foundation

extension EventNormalizer {
    static func parseInstantGrep(payload: [String: String], timestamp: Date) -> InstantGrepResult? {
        guard let query = payload["query"], !query.isEmpty else { return nil }
        let scope = payload["pathScope"] ?? payload["scope"] ?? "."
        let reportedMatchesCount = Int(payload["matchesCount"] ?? payload["count"] ?? "") ?? 0
        let durationMs = Int(payload["duration_ms"] ?? "")
        let preview = payload["previewLines"] ?? ""
        let parsedMatches = parseMatchLines(from: preview)
        let normalizedCount = parsedMatches.isEmpty ? max(0, reportedMatchesCount) : parsedMatches.count

        return InstantGrepResult(
            query: query,
            scope: scope,
            // Se preview è disponibile, il conteggio rispecchia i match parse-ati; altrimenti usa il valore riportato.
            matchesCount: normalizedCount,
            durationMs: durationMs,
            matches: parsedMatches,
            createdAt: timestamp
        )
    }

    static func parseInstantGrepFromCommand(payload: [String: String], timestamp: Date) -> InstantGrepResult? {
        guard let command = payload["command"] else { return nil }
        guard let parsedQuery = parseSearchQueryFromCommand(command) else { return nil }
        let scope = payload["cwd"] ?? "."
        let output = [payload["output"], payload["stderr"]]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        let matches = parseMatchLines(from: output)
        guard !matches.isEmpty else { return nil }

        return InstantGrepResult(
            query: parsedQuery,
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
            || lower.contains("less ")
            || lower.contains("more ")
            || lower.contains("awk ")
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

    static func parseMatchLines(from output: String, fallbackFile: String? = nil) -> [InstantGrepMatch] {
        let sanitizedOutput = output.replacingOccurrences(of: "\0", with: "\n")
        let lines = sanitizedOutput.split(separator: "\n").map(String.init)
        let fileLineRegex = try? NSRegularExpression(pattern: #"^(.*?):\s*([1-9][0-9]*):(.*)$"#)
        let lineOnlyRegex = try? NSRegularExpression(pattern: #"^\s*([1-9][0-9]*):(.*)$"#)
        var matches: [InstantGrepMatch] = []
        var currentHeadingFile: String?

        for line in lines.prefix(200) {
            // Salta i marcatori di file binari da grep/rg
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let loweredLine = trimmedLine.lowercased()
            if loweredLine.hasPrefix("binary file")
                || loweredLine.contains("binary file matches")
            {
                continue
            }
            if trimmedLine.isEmpty { continue }

            if let parsed = parseFileLineMatch(
                line: line,
                regex: fileLineRegex,
                fallbackFile: fallbackFile,
                currentHeadingFile: currentHeadingFile
            ) {
                matches.append(parsed)
                continue
            }

            if let parsed = parseLineOnlyMatch(
                line: line,
                regex: lineOnlyRegex,
                fallbackFile: fallbackFile,
                currentHeadingFile: currentHeadingFile
            ) {
                matches.append(parsed)
                continue
            }

            if !trimmedLine.contains(":") {
                currentHeadingFile = trimmedLine
            }
        }
        return matches
    }

    static func parseSearchQueryFromCommand(_ command: String) -> String? {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let args = tokenizeShellArguments(trimmed)
        guard !args.isEmpty else { return nil }

        // Ricerca case-insensitive del comando: supporta rg/grep in qualunque casing.
        if let nested = parseWrappedShellCommand(args: args) {
            return parseSearchQueryFromCommand(nested)
        }

        guard let cmdIndex = args.firstIndex(where: {
            let normalized = normalizeCommandToken($0)
            return normalized == "rg" || normalized == "grep"
        }) else {
            return nil
        }

        let valueTakingFlags: Set<String> = [
            "-g", "--glob", "-t", "--type", "-m", "--max-count",
            "-A", "-B", "-C", "-f", "--file", "-j", "--threads",
            "--include", "--exclude", "--exclude-dir", "--ignore-file",
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
        let chars = Array(input)
        var index = 0

        while index < chars.count {
            let char = chars[index]

            if char == "'" && !inDoubleQuote {
                inSingleQuote.toggle()
                index += 1
                continue
            }

            if char == "\"" && !inSingleQuote {
                inDoubleQuote.toggle()
                index += 1
                continue
            }

            if char == "\\" && !inSingleQuote {
                let nextIndex = index + 1
                if nextIndex >= chars.count {
                    current.append(char)
                    break
                }
                let next = chars[nextIndex]
                if inDoubleQuote {
                    if next == "\"" || next == "\\" || next == "$" || next == "`" {
                        current.append(next)
                        index += 2
                        continue
                    }
                    // Dentro doppi apici mantieni i backslash non speciali (es: \b regex).
                    current.append(char)
                    index += 1
                    continue
                }
                if next.isWhitespace || next == "\"" || next == "'" || next == "\\" {
                    current.append(next)
                    index += 2
                    continue
                }
                current.append(char)
                index += 1
                continue
            }

            if char.isWhitespace && !inSingleQuote && !inDoubleQuote {
                if !current.isEmpty {
                    args.append(current)
                    current.removeAll(keepingCapacity: true)
                }
                index += 1
                continue
            }

            current.append(char)
            index += 1
        }

        if !current.isEmpty {
            args.append(current)
        }
        return args
    }

    private static func parseFileLineMatch(
        line: String,
        regex: NSRegularExpression?,
        fallbackFile: String?,
        currentHeadingFile: String?
    ) -> InstantGrepMatch? {
        guard let regex else { return nil }
        let ns = line as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: line, options: [], range: range), match.numberOfRanges == 4 else {
            return nil
        }

        var file = ns.substring(with: match.range(at: 1))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if file.isEmpty {
            file = (currentHeadingFile ?? fallbackFile ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !file.isEmpty else { return nil }
        guard let number = Int(ns.substring(with: match.range(at: 2))), number > 0 else { return nil }
        let rawPreview = ns.substring(with: match.range(at: 3))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let preview = rawPreview.count > 500 ? String(rawPreview.prefix(500)) : rawPreview
        return InstantGrepMatch(file: file, line: number, preview: preview)
    }

    private static func parseLineOnlyMatch(
        line: String,
        regex: NSRegularExpression?,
        fallbackFile: String?,
        currentHeadingFile: String?
    ) -> InstantGrepMatch? {
        guard let regex else { return nil }
        let ns = line as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: line, options: [], range: range), match.numberOfRanges == 3 else {
            return nil
        }

        let file = (currentHeadingFile ?? fallbackFile ?? "<stdin>")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !file.isEmpty else { return nil }
        guard let number = Int(ns.substring(with: match.range(at: 1))), number > 0 else { return nil }
        let rawPreview = ns.substring(with: match.range(at: 2))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let preview = rawPreview.count > 500 ? String(rawPreview.prefix(500)) : rawPreview
        return InstantGrepMatch(file: file, line: number, preview: preview)
    }

    private static func parseWrappedShellCommand(args: [String]) -> String? {
        guard let first = args.first else { return nil }
        let command = normalizeCommandToken(first)
        guard command == "bash" || command == "sh" || command == "zsh" else { return nil }
        guard let cIndex = args.firstIndex(where: { $0 == "-c" || $0 == "-lc" }) else { return nil }
        let valueIndex = cIndex + 1
        guard valueIndex < args.count else { return nil }
        return args[valueIndex]
    }

    private static func normalizeCommandToken(_ token: String) -> String {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "" }
        return (trimmed as NSString).lastPathComponent.lowercased()
    }

    static func extractReadPath(from command: String) -> String? {
        let args = tokenizeShellArguments(command)
        guard !args.isEmpty else { return nil }
        guard let cmdIndex = args.firstIndex(where: {
            let normalized = normalizeCommandToken($0)
            return ["cat", "head", "tail", "sed", "less", "more", "awk"].contains(normalized)
        }) else {
            return nil
        }
        let normalizedCommand = normalizeCommandToken(args[cmdIndex])

        let flagsWithValue: Set<String> = ["-n", "-c", "-e", "-f", "--lines", "--bytes"]
        var candidates: [String] = []
        var expectValueForFlag = false

        var index = cmdIndex + 1
        while index < args.count {
            let token = args[index]
            if expectValueForFlag {
                expectValueForFlag = false
                index += 1
                continue
            }
            if token == "--" {
                index += 1
                continue
            }
            if token.hasPrefix("<<") {
                break
            }
            if flagsWithValue.contains(token.lowercased()) {
                expectValueForFlag = true
                index += 1
                continue
            }
            if token.hasPrefix("-") {
                index += 1
                continue
            }
            candidates.append(token)
            index += 1
        }

        if normalizedCommand == "awk" || normalizedCommand == "sed" {
            if candidates.count >= 2 { return candidates[1] }
            return nil
        }
        return candidates.first
    }
}
