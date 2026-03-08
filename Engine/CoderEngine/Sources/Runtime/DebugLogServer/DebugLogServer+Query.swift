import Foundation

public extension DebugLogServer {
    func query(
        severity: String? = nil,
        category: String? = nil,
        source: String? = nil,
        search: String? = nil,
        sessionId: String? = nil,
        limit: Int = 100,
        offset: Int = 0,
        after: Date? = nil
    ) -> QueryResult {
        ensureLoadedFromDiskIfNeeded()
        var filtered = entries

        if let sev = severity {
            filtered = filtered.filter { $0.severity == sev }
        }
        if let cat = category {
            filtered = filtered.filter { $0.category == cat }
        }
        if let src = source {
            filtered = filtered.filter { $0.source.contains(src) }
        }
        if let sid = sessionId ?? activeSessionId {
            filtered = filtered.filter { $0.sessionId == sid }
        }
        if let q = search, !q.isEmpty {
            let lower = q.lowercased()
            filtered = filtered.filter {
                $0.message.lowercased().contains(lower)
                || $0.source.lowercased().contains(lower)
                || ($0.detail?.lowercased().contains(lower) ?? false)
            }
        }
        if let after {
            filtered = filtered.filter { $0.timestamp > after }
        }

        let totalCount = filtered.count
        let errorCount = filtered.filter { $0.severity == "error" }.count
        let warningCount = filtered.filter { $0.severity == "warning" }.count

        let ordered = filtered.sorted { $0.timestamp > $1.timestamp }
        let normalizedOffset = max(0, offset)
        let normalizedLimit = max(1, limit)
        let sliced = Array(ordered.dropFirst(normalizedOffset).prefix(normalizedLimit))
        return QueryResult(entries: sliced, totalCount: totalCount, errorCount: errorCount, warningCount: warningCount)
    }

    func sessionSummary(sessionId: String? = nil) -> String {
        ensureLoadedFromDiskIfNeeded()
        let targetSessionId = sessionId ?? activeSessionId
        let sessionEntries = targetSessionId.map { sid in
            entries.filter { $0.sessionId == sid }
        } ?? entries

        let errors = sessionEntries.filter { $0.severity == "error" }
        let warnings = sessionEntries.filter { $0.severity == "warning" }

        var summary = "Debug Session Summary:\n"
        summary += "  Total entries: \(sessionEntries.count)\n"
        summary += "  Errors: \(errors.count)\n"
        summary += "  Warnings: \(warnings.count)\n"

        if !errors.isEmpty {
            summary += "\nErrors:\n"
            for (i, err) in errors.prefix(20).enumerated() {
                summary += "  \(i+1). [\(err.source)] \(err.message)\n"
                if let detail = err.detail {
                    let lines = detail.components(separatedBy: "\n").prefix(3)
                    for line in lines {
                        summary += "     \(line)\n"
                    }
                }
            }
        }

        if !warnings.isEmpty {
            summary += "\nWarnings (first 10):\n"
            for (i, warn) in warnings.prefix(10).enumerated() {
                summary += "  \(i+1). [\(warn.source)] \(warn.message)\n"
            }
        }

        return summary
    }

    func recentFormatted(limit: Int = 50) -> String {
        ensureLoadedFromDiskIfNeeded()
        let recent = entries.suffix(limit)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withTime, .withColonSeparatorInTime]

        return recent.map { entry in
            let ts = formatter.string(from: entry.timestamp)
            let cat = entry.category.map { "[\($0)] " } ?? ""
            return "[\(ts)] \(entry.severity.uppercased()) \(cat)\(entry.source): \(entry.message)"
        }.joined(separator: "\n")
    }

    func allEntries() -> [LogEntry] {
        ensureLoadedFromDiskIfNeeded()
        if let sid = activeSessionId {
            return entries.filter { $0.sessionId == sid }
        }
        return entries
    }

    func currentSessionId() -> String? {
        ensureLoadedFromDiskIfNeeded()
        return activeSessionId
    }

    func clear() {
        ensureLoadedFromDiskIfNeeded()
        entries.removeAll()
        persistToDisk()
    }

    func clearSession() {
        ensureLoadedFromDiskIfNeeded()
        if let sid = activeSessionId {
            entries.removeAll { $0.sessionId == sid }
        }
        persistToDisk()
    }
}
