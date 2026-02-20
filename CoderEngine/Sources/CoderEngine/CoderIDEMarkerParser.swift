import Foundation

struct CoderIDEMarker {
    let kind: String
    let payload: [String: String]
}

enum CoderIDEMarkerParser {
    private static let maxCarryLength = 2_048

    static func parse(from text: String) -> [CoderIDEMarker] {
        var markers: [CoderIDEMarker] = []
        guard let regex = try? NSRegularExpression(
            pattern: #"\[\s*CODERIDE\s*:\s*([^\]]+)\]"#,
            options: [.caseInsensitive]
        ) else {
            return markers
        }

        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        for match in regex.matches(in: text, range: full) {
            guard match.numberOfRanges >= 2 else { continue }
            let contentRange = match.range(at: 1)
            guard contentRange.location != NSNotFound else { continue }
            let raw = ns.substring(with: contentRange)
            let parts = splitEscaped(raw, separator: "|")
            guard let head = parts.first, !head.isEmpty else { continue }

            let payloadParts = Array(parts.dropFirst())
            var payload: [String: String] = [:]
            for part in payloadParts {
                let pair = splitEscaped(part, separator: "=")
                guard pair.count == 2 else { continue }
                payload[unescape(pair[0]).trimmingCharacters(in: .whitespaces)] =
                    unescape(pair[1]).trimmingCharacters(in: .whitespaces)
            }
            let kind = head.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            markers.append(CoderIDEMarker(kind: kind, payload: payload))
        }
        return markers
    }

    static func parseStreamingChunk(_ text: String, carry: inout String) -> [CoderIDEMarker] {
        let combined = carry + text
        let markers = parse(from: combined)
        carry = trailingPartialMarker(from: combined)
        if carry.count > maxCarryLength {
            carry = String(carry.suffix(maxCarryLength))
        }
        return markers
    }

    private static func trailingPartialMarker(from text: String) -> String {
        guard let openerRegex = try? NSRegularExpression(
            pattern: #"\[\s*CODERIDE\s*:"#,
            options: [.caseInsensitive]
        ) else {
            return ""
        }

        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        let matches = openerRegex.matches(in: text, range: full)
        guard let last = matches.last else { return "" }
        guard last.range.location != NSNotFound else { return "" }

        let start = last.range.location
        let candidate = ns.substring(from: start)
        return candidate.contains("]") ? "" : candidate
    }

    private static func splitEscaped(_ input: String, separator: String) -> [String] {
        guard let separatorChar = separator.first else { return [input] }
        var parts: [String] = []
        var current = ""
        var escaped = false
        for ch in input {
            if escaped {
                current.append(ch)
                escaped = false
                continue
            }
            if ch == "\\" {
                escaped = true
                continue
            }
            if ch == separatorChar {
                parts.append(current)
                current.removeAll(keepingCapacity: true)
                continue
            }
            current.append(ch)
        }
        parts.append(current)
        return parts
    }

    private static func unescape(_ input: String) -> String {
        input
            .replacingOccurrences(of: "\\|", with: "|")
            .replacingOccurrences(of: "\\=", with: "=")
            .replacingOccurrences(of: "\\]", with: "]")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }
}
