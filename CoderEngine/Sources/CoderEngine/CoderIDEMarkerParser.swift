import Foundation

struct CoderIDEMarker {
    let kind: String
    let payload: [String: String]
}

enum CoderIDEMarkerParser {
    static func parse(from text: String) -> [CoderIDEMarker] {
        var markers: [CoderIDEMarker] = []
        var searchRange: Range<String.Index>? = text.startIndex..<text.endIndex

        while let start = text.range(of: "[CODERIDE:", range: searchRange) {
            guard let end = text[start.upperBound...].firstIndex(of: "]") else { break }
            let raw = String(text[start.upperBound..<end])
            let parts = splitEscaped(raw, separator: "|")
            guard let head = parts.first, !head.isEmpty else {
                searchRange = end..<text.endIndex
                continue
            }
            let payloadParts = Array(parts.dropFirst())
            var payload: [String: String] = [:]
            for part in payloadParts {
                let pair = splitEscaped(part, separator: "=")
                guard pair.count == 2 else { continue }
                payload[unescape(pair[0]).trimmingCharacters(in: .whitespaces)] =
                    unescape(pair[1]).trimmingCharacters(in: .whitespaces)
            }
            let kind = head.trimmingCharacters(in: .whitespaces)
            markers.append(CoderIDEMarker(kind: kind, payload: payload))
            searchRange = end..<text.endIndex
        }
        return markers
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
