import Foundation

extension UnifiedToolRuntime {
    func parseDebugDataArg(_ raw: String?) -> [String: String] {
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [:] }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{"),
           let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            var out: [String: String] = [:]
            for (key, value) in json { out[key] = "\(value)" }
            return out
        }
        var out: [String: String] = [:]
        for pair in raw.split(separator: ",") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if kv.count == 2 {
                out[kv[0].trimmingCharacters(in: .whitespacesAndNewlines)] = kv[1].trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return out
    }

    func parseDebugDataValue(_ value: Any?) -> [String: String] {
        guard let value else { return [:] }
        if let stringValue = value as? String {
            return parseDebugDataArg(stringValue)
        }
        if let dict = value as? [String: String] {
            return dict
        }
        if let dict = value as? [String: Any] {
            var out: [String: String] = [:]
            for (key, raw) in dict {
                out[key] = String(describing: raw)
            }
            return out
        }
        return [:]
    }

    func enrichedDebugDetail(detail: String?, stackTrace: String?, tags: String?) -> String? {
        var parts: [String] = []
        if let detail, !detail.isEmpty {
            parts.append(detail)
        }
        if let stackTrace, !stackTrace.isEmpty {
            parts.append("Stack Trace:\n\(stackTrace)")
        }
        if let tags, !tags.isEmpty {
            parts.append("Tags: \(tags)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }

    func resolveHypothesisLookup(_ rawIdentifier: String) -> HypothesisLookupResult {
        let normalized = rawIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return .notFound }

        if let exact = debugHypotheses.keys.first(where: { $0.lowercased() == normalized }) {
            return .resolved(exact)
        }

        let short = String(normalized.prefix(8))
        let candidates = debugHypotheses.keys.filter { hypothesisID in
            let normalizedExisting = hypothesisID.lowercased()
            return normalizedExisting.hasPrefix(normalized)
                || String(normalizedExisting.prefix(8)) == short
        }

        if candidates.count == 1, let only = candidates.first {
            return .resolved(only)
        }
        if candidates.count > 1 {
            let prefixes = Array(Set(candidates.map { String($0.prefix(8)) })).sorted()
            return .ambiguous(prefixes)
        }
        return .notFound
    }

    func entryMatchesHypothesis(_ entry: DebugLogServer.LogEntry, filter hypothesisId: String?) -> Bool {
        let normalizedFilter = (hypothesisId ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalizedFilter.isEmpty else { return true }

        let short = String(normalizedFilter.prefix(8))
        let entryHypothesis = (entry.hypothesisId ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if !entryHypothesis.isEmpty {
            if entryHypothesis == normalizedFilter {
                return true
            }
            if String(entryHypothesis.prefix(8)) == short {
                return true
            }
        }

        let detail = (entry.detail ?? "").lowercased()
        let message = entry.message.lowercased()
        return detail.contains(normalizedFilter)
            || message.contains(normalizedFilter)
            || detail.contains("[h:\(short)]")
            || message.contains("[h:\(short)]")
            || message.contains(short)
    }

    func normalizeHypothesisStatus(_ status: String, fallback: String) -> String {
        switch status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "proposed", "investigating", "confirmed", "rejected":
            return status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        default:
            return fallback
        }
    }

}
