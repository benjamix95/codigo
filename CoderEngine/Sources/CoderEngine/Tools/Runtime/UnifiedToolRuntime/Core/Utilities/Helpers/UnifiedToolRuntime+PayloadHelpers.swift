import Foundation

extension UnifiedToolRuntime {

    enum HypothesisLookupResult {
        case resolved(String)
        case notFound
        case ambiguous([String])
    }

    // MARK: - Result Builders

    func success(_ payload: [String: String], startDate: Date) -> ToolResult {
        ToolResult(ok: true, payload: payload, durationMs: max(1, Int(Date().timeIntervalSince(startDate) * 1000)))
    }

    func failure(
        _ message: String,
        errorCode: String,
        startDate: Date,
        payload: [String: String] = [:]
    ) -> ToolResult {
        var p = payload
        p["title"] = p["title"] ?? "Tool error"
        p["detail"] = message
        p["stderr"] = message
        p["error_code"] = errorCode
        return ToolResult(ok: false, payload: p, durationMs: max(1, Int(Date().timeIntervalSince(startDate) * 1000)))
    }

    // MARK: - Diff & JSON Helpers

    func buildDiffPreview(old: String, new: String) -> String {
        let oldLines = old.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let newLines = new.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var out: [String] = []
        let maxCount = min(max(oldLines.count, newLines.count), 80)
        for i in 0..<maxCount {
            let oldLine = i < oldLines.count ? oldLines[i] : nil
            let newLine = i < newLines.count ? newLines[i] : nil
            if oldLine == newLine { continue }
            if let oldLine {
                out.append("- \(oldLine)")
            }
            if let newLine {
                out.append("+ \(newLine)")
            }
            if out.count >= 40 { break }
        }
        return out.joined(separator: "\n")
    }

    func parseJSONObject(from raw: String) throws -> Any {
        guard let data = raw.data(using: .utf8) else {
            throw ToolRuntimeError.validation("JSON patch non valido")
        }
        return try JSONSerialization.jsonObject(with: data)
    }

    func prettyJSON(_ obj: Any) -> String {
        guard JSONSerialization.isValidJSONObject(obj),
              let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8)
        else {
            return String(describing: obj)
        }
        return text
    }

    func parseEmbeddedArgs(_ raw: String?) -> [String: String] {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }
        var out: [String: String] = [:]
        for (k, v) in json {
            if let s = v as? String {
                out[k] = s
            } else if let b = v as? Bool {
                out[k] = b ? "true" : "false"
            } else if let n = v as? NSNumber {
                out[k] = n.stringValue
            } else if let serialized = try? JSONSerialization.data(withJSONObject: v),
                      let str = String(data: serialized, encoding: .utf8)
            {
                out[k] = str
            } else {
                out[k] = String(describing: v)
            }
        }
        return out
    }

    // MARK: - Workspace Path Normalization

    func normalizeWorkspacePaths(_ paths: [String]) -> [String] {
        var normalized = Set<String>()
        for rawPath in paths {
            let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let value = URL(fileURLWithPath: trimmed).standardizedFileURL.path
            normalized.insert(value)
        }
        return normalized.sorted()
    }
}
