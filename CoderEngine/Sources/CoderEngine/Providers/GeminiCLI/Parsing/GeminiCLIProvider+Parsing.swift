import Foundation

public extension GeminiCLIProvider {
    static func parseRawEvent(from json: [String: Any]) -> (type: String, payload: [String: String])? {
        let item = (json["item"] as? [String: Any]) ?? json
        let type = firstString(in: item, keys: ["type", "event_type"])?.lowercased() ?? ""
        if type == "reasoning" || type == "thinking" {
            let text = firstString(in: item, keys: ["text", "output", "content", "result", "message"]) ?? ""
            guard !text.isEmpty else { return nil }
            var payload: [String: String] = [
                "title": "Reasoning",
                "detail": String(text.prefix(200)) + (text.count > 200 ? "…" : ""),
                "output": String(text.prefix(6_000)),
            ]
            if SwarmMetadataResolver.applySwarmMetadata(to: &payload, from: item, forceGroupID: true) {
                return ("reasoning", payload)
            }
            payload["group_id"] = "reasoning-stream"
            return ("reasoning", payload)
        }

        let rawTool = firstString(in: item, keys: ["tool", "name"]) ?? type
        if let mapped = ProviderToolEventMapper.map(
            toolName: rawTool,
            payload: item,
            typeHint: type
        ) {
            return withSwarmMetadata(mapped, item: item)
        }

        if !type.isEmpty {
            if let mappedFromType = ProviderToolEventMapper.map(
                toolName: type,
                payload: item,
                typeHint: type
            ) {
                return withSwarmMetadata(mappedFromType, item: item)
            }
        }

        return nil
    }

    static func withSwarmMetadata(
        _ mapped: (type: String, payload: [String: String]),
        item: [String: Any]
    ) -> (type: String, payload: [String: String]) {
        var payload = mapped.payload
        SwarmMetadataResolver.applySwarmMetadata(to: &payload, from: item)
        return (mapped.type, payload)
    }

    static func parseStreamJSONPayloads(from rawLine: String, carry: inout String) -> [[String: Any]] {
        let cleaned = cleanedJSONCandidateLine(rawLine)
        guard !cleaned.isEmpty else { return [] }

        if let direct = decodeJSONDictionary(cleaned) {
            return [direct]
        }

        // Handle concatenated/noisy objects only when the line appears to contain
        // top-level JSON objects, avoiding nested objects from pretty-printed lines.
        if let first = cleaned.first, first == "{" {
            let inlinePayloads = extractJSONObjectStrings(from: cleaned).compactMap { decodeJSONDictionary($0) }
            if !inlinePayloads.isEmpty {
                return inlinePayloads
            }
        }

        if !carry.isEmpty || looksLikeJSONFragment(cleaned) {
            if !carry.isEmpty {
                carry.append("\n")
            }
            carry.append(cleaned)

            if let full = decodeJSONDictionary(carry) {
                carry = ""
                return [full]
            }

            // Safety valve: prevent unbounded buffer growth on unexpected output.
            if carry.count > 200_000 {
                carry = String(carry.suffix(50_000))
            }
        }

        return []
    }

    static func flushStreamJSONPayloads(carry: inout String) -> [[String: Any]] {
        let cleaned = carry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            carry = ""
            return []
        }
        if let full = decodeJSONDictionary(cleaned) {
            carry = ""
            return [full]
        }
        let payloads = extractJSONObjectStrings(from: cleaned).compactMap { decodeJSONDictionary($0) }
        carry = ""
        return payloads
    }

    static func extractText(from obj: Any) -> String? {
        if let dict = obj as? [String: Any] {
            // Prefer canonical Gemini response fields and avoid metadata.
            for key in ["response", "result", "output", "text"] {
                if let value = dict[key], let txt = nonEmptyString(value) {
                    return txt
                }
            }

            for key in ["content", "message"] {
                if let value = dict[key], let txt = nonEmptyString(value) {
                    return txt
                }
            }

            let metadataKeys: Set<String> = [
                "session_id", "id", "status", "stats", "models", "model", "tools", "files",
                "usage", "tokens", "api", "totalrequests", "totalerrors", "totallatencyms",
                "prompt", "input", "cached", "thoughts", "candidates", "total", "durationms"
            ]
            for (key, value) in dict {
                if metadataKeys.contains(key.lowercased()) {
                    continue
                }
                if let nested = extractText(from: value), !nested.isEmpty {
                    return nested
                }
            }
        } else if let arr = obj as? [Any] {
            var chunks: [String] = []
            for value in arr {
                if let nested = extractText(from: value), !nested.isEmpty {
                    chunks.append(nested)
                }
            }
            if !chunks.isEmpty { return chunks.joined(separator: "\n") }
        }
        return nil
    }
}
