import Foundation

public extension GeminiCLIProvider {
    static func looksLikeJSONFragment(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if let first = trimmed.first, ["{", "}", "[", "]", "\"", ","].contains(first) {
            return true
        }
        return trimmed.contains(":")
    }

    static func cleanedJSONCandidateLine(_ raw: String) -> String {
        let scalars = raw.unicodeScalars.filter { scalar in
            scalar.value == 0x09 || scalar.value >= 0x20
        }
        return String(String.UnicodeScalarView(scalars))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decodeJSONDictionary(_ raw: String) -> [String: Any]? {
        guard let data = raw.data(using: .utf8),
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
}
