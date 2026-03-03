import Foundation

extension CoderIDEMCPServerApp {
    static func structuredMCPEditPayload(
        toolName: String,
        toolCallID: String,
        payload: [String: String],
        isError: Bool
    ) -> [String: String] {
        var structured: [String: String] = [:]
        structured["source"] = "mcp"
        structured["tool"] = toolName
        structured["tool_call_id"] = firstNonEmpty(payload: payload, keys: ["tool_call_id", "call_id", "id"])
            ?? toolCallID
        structured["status"] = firstNonEmpty(payload: payload, keys: ["status"]) ?? (isError ? "failed" : "completed")
        structured["change_type"] = firstNonEmpty(
            payload: payload,
            keys: ["change_type", "operation", "action", "edit_type"]
        ) ?? toolName
        if let path = firstNonEmpty(
            payload: payload,
            keys: ["path", "file", "file_path", "target_path", "relative_path"]
        ) {
            structured["path"] = path
        }
        if let added = firstNonEmpty(payload: payload, keys: ["linesAdded", "additions", "insertions", "added"]) {
            structured["linesAdded"] = added
        }
        if let removed = firstNonEmpty(payload: payload, keys: ["linesRemoved", "deletions", "removed", "deletions_count"]) {
            structured["linesRemoved"] = removed
        }
        if let diff = firstNonEmpty(
            payload: payload,
            keys: ["diffPreview", "diff", "patch", "unified_diff", "changes_preview"]
        ) {
            structured["diffPreview"] = String(diff.prefix(12_000))
        }
        if let detail = firstNonEmpty(payload: payload, keys: ["detail"]) {
            structured["detail"] = detail
        }
        if let title = firstNonEmpty(payload: payload, keys: ["title"]) {
            structured["title"] = title
        }
        return structured
    }

    static func payloadScore(payload: [String: String]) -> Int {
        var score = payload.count
        if let status = payload["status"]?.lowercased(), status == "completed" {
            score += 100
        }
        if payload["linesAdded"] != nil || payload["linesRemoved"] != nil {
            score += 60
        }
        if payload["diffPreview"] != nil || payload["patch"] != nil || payload["diff"] != nil {
            score += 60
        }
        if payload["path"] != nil || payload["file"] != nil {
            score += 20
        }
        return score
    }

    static func firstNonEmpty(payload: [String: String], keys: [String]) -> String? {
        for key in keys {
            let value = (payload[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                return payload[key]
            }
        }
        return nil
    }

    static func encodeJSONObjectString(_ object: [String: String]) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
