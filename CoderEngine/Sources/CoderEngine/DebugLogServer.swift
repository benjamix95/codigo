import Foundation

/// Actor-based debug log server that captures structured log entries,
/// writes them to a local file, and provides query capabilities.
/// Acts as the "debug MCP server" — a persistent log store the LLM agent
/// can write to and read from during debug sessions.
public actor DebugLogServer {

    // MARK: - Types

    public struct LogEntry: Codable, Sendable {
        public let id: String
        public let timestamp: Date
        public let severity: String   // error, warning, info, verbose, trace
        public let source: String     // file:line or module
        public let message: String
        public let detail: String?    // stack trace, extra context
        public let category: String?  // compiler, runtime, test, network, custom, instrumentation
        public let sessionId: String?
        public let runId: String?          // groups logs from a single reproduce run
        public let hypothesisId: String?   // links to hypothesis being tested
        public let data: [String: String]? // arbitrary key-value data (variable values, timing)

        public init(
            severity: String,
            source: String,
            message: String,
            detail: String? = nil,
            category: String? = nil,
            sessionId: String? = nil,
            runId: String? = nil,
            hypothesisId: String? = nil,
            data: [String: String]? = nil
        ) {
            self.id = UUID().uuidString
            self.timestamp = Date()
            self.severity = severity
            self.source = source
            self.message = message
            self.detail = detail
            self.category = category
            self.sessionId = sessionId
            self.runId = runId
            self.hypothesisId = hypothesisId
            self.data = data
        }
    }

    public struct QueryResult: Sendable {
        public let entries: [LogEntry]
        public let totalCount: Int
        public let errorCount: Int
        public let warningCount: Int

        public func filteredByDetail(_ predicate: (String?) -> Bool) -> QueryResult {
            let filtered = entries.filter { predicate($0.detail) }
            return QueryResult(
                entries: filtered,
                totalCount: filtered.count,
                errorCount: filtered.filter { $0.severity == "error" }.count,
                warningCount: filtered.filter { $0.severity == "warning" }.count
            )
        }

        public func filteredByTime(after cutoff: Date) -> QueryResult {
            let filtered = entries.filter { $0.timestamp > cutoff }
            return QueryResult(
                entries: filtered,
                totalCount: filtered.count,
                errorCount: filtered.filter { $0.severity == "error" }.count,
                warningCount: filtered.filter { $0.severity == "warning" }.count
            )
        }

        public func filtered(_ predicate: (LogEntry) -> Bool) -> QueryResult {
            let filtered = entries.filter(predicate)
            return QueryResult(
                entries: filtered,
                totalCount: filtered.count,
                errorCount: filtered.filter { $0.severity == "error" }.count,
                warningCount: filtered.filter { $0.severity == "warning" }.count
            )
        }

        public func filteredByHypothesisId(_ hypothesisId: String) -> QueryResult {
            let normalized = hypothesisId
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard !normalized.isEmpty else { return self }
            let short = String(normalized.prefix(8))

            let filtered = entries.filter { entry in
                if let entryHypothesis = entry.hypothesisId?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased(),
                   !entryHypothesis.isEmpty
                {
                    if entryHypothesis == normalized {
                        return true
                    }
                    let entryShort = String(entryHypothesis.prefix(8))
                    if entryShort == short {
                        return true
                    }
                }

                let detail = (entry.detail ?? "").lowercased()
                let message = entry.message.lowercased()
                return detail.contains(normalized)
                    || message.contains(normalized)
                    || detail.contains("[h:\(short)]")
                    || message.contains("[h:\(short)]")
            }

            return QueryResult(
                entries: filtered,
                totalCount: filtered.count,
                errorCount: filtered.filter { $0.severity == "error" }.count,
                warningCount: filtered.filter { $0.severity == "warning" }.count
            )
        }
    }

    // MARK: - State

    private var entries: [LogEntry] = []
    private let logFileURL: URL
    private let maxEntries: Int
    private var activeSessionId: String?
    private var hasLoadedFromDisk = false

    // MARK: - Init

    public init(maxEntries: Int = 5000) {
        self.maxEntries = maxEntries
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let debugDir = cacheDir.appendingPathComponent("com.codigo.debug", isDirectory: true)
        try? FileManager.default.createDirectory(at: debugDir, withIntermediateDirectories: true)
        self.logFileURL = debugDir.appendingPathComponent("debug_log.jsonl")
    }

    // MARK: - Session Management

    public func startSession() -> String {
        ensureLoadedFromDiskIfNeeded()
        let sessionId = UUID().uuidString
        activeSessionId = sessionId
        let entry = LogEntry(
            severity: "info",
            source: "debug_server",
            message: "Debug session started",
            category: "system",
            sessionId: sessionId
        )
        append(entry)
        return sessionId
    }

    public func endSession() {
        ensureLoadedFromDiskIfNeeded()
        if let sid = activeSessionId {
            let entry = LogEntry(
                severity: "info",
                source: "debug_server",
                message: "Debug session ended",
                category: "system",
                sessionId: sid
            )
            append(entry)
        }
        activeSessionId = nil
    }

    // MARK: - Write

    public func log(
        severity: String,
        source: String,
        message: String,
        detail: String? = nil,
        category: String? = nil,
        runId: String? = nil,
        hypothesisId: String? = nil,
        data: [String: String]? = nil
    ) {
        ensureLoadedFromDiskIfNeeded()
        let entry = LogEntry(
            severity: severity,
            source: source,
            message: message,
            detail: detail,
            category: category,
            sessionId: activeSessionId,
            runId: runId,
            hypothesisId: hypothesisId,
            data: data
        )
        append(entry)
    }

    /// Log a runtime instrumentation entry (Cursor-style: tied to run + hypothesis)
    public func logRuntime(
        source: String,
        message: String,
        severity: String = "info",
        detail: String? = nil,
        category: String = "instrumentation",
        data: [String: String] = [:],
        runId: String? = nil,
        hypothesisId: String? = nil
    ) {
        ensureLoadedFromDiskIfNeeded()
        let entry = LogEntry(
            severity: severity,
            source: source,
            message: message,
            detail: detail,
            category: category,
            sessionId: activeSessionId,
            runId: runId,
            hypothesisId: hypothesisId,
            data: data.isEmpty ? nil : data
        )
        append(entry)
    }

    /// Query runtime logs for a specific run
    public func queryRuntime(
        runId: String? = nil,
        hypothesisId: String? = nil,
        limit: Int = 100
    ) -> [LogEntry] {
        ensureLoadedFromDiskIfNeeded()
        var filtered = entries.filter { $0.category == "instrumentation" || $0.category == "runtime" }
        if let rid = runId {
            filtered = filtered.filter { $0.runId == rid }
        }
        if let hid = hypothesisId {
            filtered = filtered.filter { $0.hypothesisId == hid }
        }
        return Array(filtered.suffix(limit))
    }

    public func logBuildOutput(_ output: String, source: String = "build") {
        ensureLoadedFromDiskIfNeeded()
        // Parse structured diagnostics from build output
        let lines = output.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let severity: String
            if trimmed.contains("error:") || trimmed.contains("Error:") {
                severity = "error"
            } else if trimmed.contains("warning:") || trimmed.contains("Warning:") {
                severity = "warning"
            } else if trimmed.contains("note:") {
                severity = "info"
            } else {
                severity = "verbose"
            }

            append(LogEntry(
                severity: severity,
                source: source,
                message: trimmed,
                category: "compiler",
                sessionId: activeSessionId
            ))
        }
    }

    public func logTestOutput(_ output: String, source: String = "test") {
        ensureLoadedFromDiskIfNeeded()
        let lines = output.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let severity: String
            if trimmed.contains("FAIL") || trimmed.contains("failed") {
                severity = "error"
            } else if trimmed.contains("PASS") || trimmed.contains("passed") {
                severity = "info"
            } else {
                severity = "verbose"
            }

            append(LogEntry(
                severity: severity,
                source: source,
                message: trimmed,
                category: "test",
                sessionId: activeSessionId
            ))
        }
    }

    public func logRuntimeError(_ error: String, source: String, stackTrace: String? = nil) {
        ensureLoadedFromDiskIfNeeded()
        append(LogEntry(
            severity: "error",
            source: source,
            message: error,
            detail: stackTrace,
            category: "runtime",
            sessionId: activeSessionId
        ))
    }

    // MARK: - Query

    public func query(
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

    /// Get a summary of current session errors and warnings
    public func sessionSummary(sessionId: String? = nil) -> String {
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

    /// Get recent entries as formatted text for LLM context
    public func recentFormatted(limit: Int = 50) -> String {
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

    /// All entries in the current session
    public func allEntries() -> [LogEntry] {
        ensureLoadedFromDiskIfNeeded()
        if let sid = activeSessionId {
            return entries.filter { $0.sessionId == sid }
        }
        return entries
    }

    /// Current active session ID
    public func currentSessionId() -> String? {
        ensureLoadedFromDiskIfNeeded()
        return activeSessionId
    }

    // MARK: - Clear

    public func clear() {
        ensureLoadedFromDiskIfNeeded()
        entries.removeAll()
        persistToDisk()
    }

    public func clearSession() {
        ensureLoadedFromDiskIfNeeded()
        if let sid = activeSessionId {
            entries.removeAll { $0.sessionId == sid }
        }
        persistToDisk()
    }

    // MARK: - Persistence

    private static let maxFileSize: UInt64 = 5 * 1024 * 1024 // 5 MB
    private var appendsSinceLastSizeCheck: Int = 0

    private func append(_ entry: LogEntry) {
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        if let data = try? JSONEncoder().encode(entry),
           let line = String(data: data, encoding: .utf8) {
            appendLineToDisk(line)
        }
        appendsSinceLastSizeCheck += 1
        if appendsSinceLastSizeCheck >= 200 {
            appendsSinceLastSizeCheck = 0
            rotateFileIfNeeded()
        }
    }

    private func appendLineToDisk(_ line: String) {
        let lineData = (line + "\n").data(using: .utf8) ?? Data()
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            _ = FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        }

        if let handle = try? FileHandle(forWritingTo: logFileURL) {
            handle.seekToEndOfFile()
            handle.write(lineData)
            try? handle.close()
            return
        }

        // Avoid atomic overwrite fallback here: preserve in-memory entries and rewrite safely.
        persistToDisk()
    }

    private func rotateFileIfNeeded() {
        guard currentLogFileSize() > Self.maxFileSize else { return }
        persistToDisk()
        guard currentLogFileSize() > Self.maxFileSize else { return }
        trimEntriesToFitFileSize(Self.maxFileSize)
        persistToDisk()
    }

    private func currentLogFileSize() -> UInt64 {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: logFileURL.path),
              let fileSize = attrs[.size] as? UInt64 else {
            return 0
        }
        return fileSize
    }

    private func trimEntriesToFitFileSize(_ maxBytes: UInt64) {
        guard !entries.isEmpty else { return }
        let maxBytesInt = Int(min(maxBytes, UInt64(Int.max)))
        var kept: [LogEntry] = []
        var usedBytes = 0

        for entry in entries.reversed() {
            guard let encoded = try? JSONEncoder().encode(entry) else { continue }
            let lineBytes = encoded.count + 1 // newline
            if !kept.isEmpty, usedBytes + lineBytes > maxBytesInt {
                break
            }
            if kept.isEmpty, lineBytes > maxBytesInt {
                kept.append(entry)
                break
            }
            kept.append(entry)
            usedBytes += lineBytes
        }

        entries = kept.reversed()
    }

    private func persistToDisk() {
        let lines = entries.compactMap { entry -> String? in
            guard let data = try? JSONEncoder().encode(entry) else { return nil }
            return String(data: data, encoding: .utf8)
        }
        try? lines.joined(separator: "\n").write(to: logFileURL, atomically: true, encoding: .utf8)
    }

    private func ensureLoadedFromDiskIfNeeded() {
        guard !hasLoadedFromDisk else { return }
        loadFromDisk()
    }

    /// Load entries from disk on startup
    public func loadFromDisk() {
        hasLoadedFromDisk = true
        entries.removeAll(keepingCapacity: true)
        guard let content = try? String(contentsOf: logFileURL, encoding: .utf8) else { return }
        let decoder = JSONDecoder()
        let lines = content.components(separatedBy: "\n")
        for line in lines {
            guard !line.isEmpty, let data = line.data(using: .utf8),
                  let entry = try? decoder.decode(LogEntry.self, from: data) else { continue }
            entries.append(entry)
        }
        let needsTrim = entries.count > maxEntries
        if needsTrim {
            entries.removeFirst(entries.count - maxEntries)
        }
        if needsTrim || currentLogFileSize() > Self.maxFileSize {
            trimEntriesToFitFileSize(Self.maxFileSize)
            persistToDisk()
        }
    }
}
