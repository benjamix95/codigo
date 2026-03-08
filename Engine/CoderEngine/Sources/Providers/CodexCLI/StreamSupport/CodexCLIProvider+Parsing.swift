import Foundation

extension CodexCLIProvider {
    struct CodexStreamParserState {
        struct TurnState {
            var lastObservedAgentText = ""
            var lastValidAgentMessage = ""
            var emittedAnyAssistantDelta = false
        }

        var workspacePath: String?
        var turn = TurnState()
        var scrubCarry = ""
        var emittedRawKeys: Set<String> = []
        var emittedContextCompacted = false
        var invokeSwarmEmitted = false
        var jsonCarry = ""
        let maxJSONCarryLength = 128_000
        /// Accumulates visible text emitted across all turns so far, used to
        /// move intermediate turn text into the reasoning/thinking block when
        /// a new turn starts.
        var cumulativeVisibleText = ""
        var turnCount = 0

        init(workspacePath: String? = nil) {
            self.workspacePath = workspacePath
        }

        mutating func resetTurn() {
            turn = TurnState()
            scrubCarry = ""
            emittedRawKeys.removeAll(keepingCapacity: true)
        }
    }

    static func parseStreamJSONPayloads(from rawLine: String) -> [[String: Any]] {
        var state = CodexStreamParserState()
        return parseStreamJSONPayloads(from: rawLine, state: &state)
    }

    static func parseStreamJSONPayloads(
        from rawLine: String,
        state: inout CodexStreamParserState
    ) -> [[String: Any]] {
        let cleaned = cleanedJSONCandidateLine(rawLine)
        guard !cleaned.isEmpty else { return [] }

        if state.jsonCarry.isEmpty, let direct = decodeJSONDictionary(cleaned) {
            return [direct]
        }

        if !state.jsonCarry.isEmpty {
            state.jsonCarry += "\n"
        }
        state.jsonCarry += cleaned
        let (extracted, remainder) = extractJSONObjectStringsAndRemainder(from: state.jsonCarry)
        state.jsonCarry = String(remainder.suffix(state.maxJSONCarryLength))
        guard !extracted.isEmpty else { return [] }
        return extracted.compactMap { decodeJSONDictionary($0) }
    }

    static func cleanedJSONCandidateLine(_ raw: String) -> String {
        let scalars = raw.unicodeScalars.filter { scalar in
            // Keep tab and printable characters; remove control chars (\0, \b, ^D, etc).
            scalar.value == 0x09 || scalar.value >= 0x20
        }
        return String(String.UnicodeScalarView(scalars))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decodeJSONDictionary(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    static func extractJSONObjectStrings(from line: String) -> [String] {
        var results: [String] = []
        var depth = 0
        var inString = false
        var escaped = false
        var startIndex: String.Index?

        var index = line.startIndex
        while index < line.endIndex {
            let ch = line[index]

            if inString {
                if escaped {
                    escaped = false
                } else if ch == "\\" {
                    escaped = true
                } else if ch == "\"" {
                    inString = false
                }
                index = line.index(after: index)
                continue
            }

            if ch == "\"" {
                inString = true
                index = line.index(after: index)
                continue
            }

            if ch == "{" {
                if depth == 0 {
                    startIndex = index
                }
                depth += 1
            } else if ch == "}" {
                if depth > 0 {
                    depth -= 1
                    if depth == 0, let start = startIndex {
                        let end = line.index(after: index)
                        results.append(String(line[start..<end]))
                        startIndex = nil
                    }
                }
            }

            index = line.index(after: index)
        }

        return results
    }

    static func extractJSONObjectStringsAndRemainder(from text: String) -> ([String], String) {
        var results: [String] = []
        var depth = 0
        var inString = false
        var escaped = false
        var startIndex: String.Index?
        var lastConsumed = text.startIndex

        var index = text.startIndex
        while index < text.endIndex {
            let ch = text[index]

            if inString {
                if escaped {
                    escaped = false
                } else if ch == "\\" {
                    escaped = true
                } else if ch == "\"" {
                    inString = false
                }
                index = text.index(after: index)
                continue
            }

            if ch == "\"" {
                inString = true
                index = text.index(after: index)
                continue
            }

            if ch == "{" {
                if depth == 0 {
                    startIndex = index
                }
                depth += 1
            } else if ch == "}" {
                if depth > 0 {
                    depth -= 1
                    if depth == 0, let start = startIndex {
                        let end = text.index(after: index)
                        results.append(String(text[start..<end]))
                        startIndex = nil
                        lastConsumed = end
                    }
                }
            }
            index = text.index(after: index)
        }

        if depth > 0, let start = startIndex {
            return (results, String(text[start...]))
        }
        if lastConsumed < text.endIndex {
            let trailing = String(text[lastConsumed...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return (results, trailing)
        }
        return (results, "")
    }
}
