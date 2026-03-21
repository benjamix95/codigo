import Foundation

public enum IDEStateTodoArgumentParser {
    public static func parse(_ raw: Any?) -> [[String: Any]]? {
        guard let raw else { return nil }

        if let array = raw as? [[String: Any]] {
            return normalize(array)
        }
        if let object = raw as? [String: Any] {
            return normalize([object])
        }
        if let array = raw as? [Any] {
            return normalize(array)
        }
        if let rawString = raw as? String {
            return parseString(rawString)
        }
        return nil
    }

    /// Batch-mode parsing for the `todos` field.
    /// Structured arrays remain valid, but a native single object is rejected
    /// so malformed MCP payloads do not silently downgrade into a valid batch.
    public static func parseBatchCollection(_ raw: Any?) -> [[String: Any]]? {
        guard let raw else { return nil }

        if let array = raw as? [[String: Any]] {
            return normalize(array)
        }
        if let array = raw as? [Any] {
            return normalize(array)
        }
        if raw is [String: Any] {
            return nil
        }
        if let rawString = raw as? String {
            return parseString(rawString)
        }
        return nil
    }

    private static func parseString(_ rawString: String) -> [[String: Any]]? {
        let trimmed = rawString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        for candidate in jsonCandidates(from: trimmed) {
            guard let data = candidate.data(using: .utf8),
                  let decoded = try? JSONSerialization.jsonObject(with: data)
            else {
                continue
            }
            if let parsed = parse(decoded) {
                return parsed
            }
        }

        return parseChecklist(trimmed)
    }

    private static func jsonCandidates(from raw: String) -> [String] {
        var candidates: [String] = [raw]

        if raw.hasPrefix("```"), raw.hasSuffix("```") {
            let lines = raw.components(separatedBy: .newlines)
            if lines.count >= 3 {
                let inner = lines.dropFirst().dropLast().joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !inner.isEmpty {
                    candidates.append(inner)
                }
            }
        }

        if let firstArray = raw.firstIndex(of: "["),
           let lastArray = raw.lastIndex(of: "]"),
           firstArray < lastArray {
            candidates.append(String(raw[firstArray...lastArray]))
        }
        if let firstObject = raw.firstIndex(of: "{"),
           let lastObject = raw.lastIndex(of: "}"),
           firstObject < lastObject {
            candidates.append(String(raw[firstObject...lastObject]))
        }

        var unique: [String] = []
        var seen = Set<String>()
        for candidate in candidates {
            if seen.insert(candidate).inserted {
                unique.append(candidate)
            }
        }
        return unique
    }

    private static func normalize(_ rawItems: [Any]) -> [[String: Any]]? {
        var items: [[String: Any]] = []
        for rawItem in rawItems {
            guard let item = normalizeItem(rawItem) else { continue }
            items.append(item)
        }
        return items.isEmpty && !rawItems.isEmpty ? nil : items
    }

    private static func normalizeItem(_ rawItem: Any) -> [String: Any]? {
        if let item = rawItem as? [String: Any] {
            return item
        }
        if let text = rawItem as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return [
                "content": trimmed,
                "status": "pending",
            ]
        }
        if let number = rawItem as? NSNumber {
            return [
                "content": number.stringValue,
                "status": "pending",
            ]
        }
        return nil
    }

    private static func parseChecklist(_ raw: String) -> [[String: Any]]? {
        let lines = raw.components(separatedBy: .newlines)
        let looksLikeChecklist = lines.count > 1 || lines.contains(where: lineLooksLikeChecklist(_:))
        guard looksLikeChecklist else {
            guard !raw.hasPrefix("{"),
                  !raw.hasPrefix("[")
            else {
                return nil
            }
            return [[
                "content": raw,
                "status": "pending",
            ]]
        }

        var items: [[String: Any]] = []

        for line in lines {
            guard let item = parseChecklistLine(line) else { continue }
            items.append(item)
        }

        if !items.isEmpty {
            return items
        }
        return nil
    }

    private static func parseChecklistLine(_ line: String) -> [String: Any]? {
        var working = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !working.isEmpty else { return nil }

        if working.hasPrefix("- ") || working.hasPrefix("* ") || working.hasPrefix("+ ") {
            working = String(working.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            let pattern = #"^\d+[\.\)]\s+"#
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(
                   in: working,
                   range: NSRange(location: 0, length: working.utf16.count)
               ),
               let range = Range(match.range, in: working) {
                working.removeSubrange(range)
                working = working.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        let lower = working.lowercased()
        let status: String
        if lower.hasPrefix("[x]") {
            status = "done"
            working = String(working.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if lower.hasPrefix("[~]") || lower.hasPrefix("[-]") {
            status = "in_progress"
            working = String(working.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if lower.hasPrefix("[!]") {
            status = "blocked"
            working = String(working.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else if lower.hasPrefix("[ ]") {
            status = "pending"
            working = String(working.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            status = "pending"
        }

        guard !working.isEmpty else { return nil }
        return [
            "content": working,
            "status": status,
        ]
    }

    private static func lineLooksLikeChecklist(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.hasPrefix("- [") || trimmed.hasPrefix("* [") || trimmed.hasPrefix("+ [") {
            return true
        }
        if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("+ ") {
            return true
        }
        let pattern = #"^\d+[\.\)]\s+"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(location: 0, length: trimmed.utf16.count)
        return regex.firstMatch(in: trimmed, range: range) != nil
    }
}
