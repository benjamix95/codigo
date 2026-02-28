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
    }

    // MARK: - State

    private var entries: [LogEntry] = []
    private let logFileURL: URL
    private let maxEntries: Int
    private var activeSessionId: String?

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
        category: String? = nil
    ) {
        let entry = LogEntry(
            severity: severity,
            source: source,
            message: message,
            detail: detail,
            category: category,
            sessionId: activeSessionId
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
        offset: Int = 0
    ) -> QueryResult {
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

        let totalCount = filtered.count
        let errorCount = filtered.filter { $0.severity == "error" }.count
        let warningCount = filtered.filter { $0.severity == "warning" }.count

        let sliced = Array(filtered.dropFirst(offset).prefix(limit))
        return QueryResult(entries: sliced, totalCount: totalCount, errorCount: errorCount, warningCount: warningCount)
    }

    /// Get a summary of current session errors and warnings
    public func sessionSummary() -> String {
        let sessionEntries = activeSessionId.map { sid in
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
        let recent = entries.suffix(limit)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withTime, .withColonSeparatorInTime]

        return recent.map { entry in
            let ts = formatter.string(from: entry.timestamp)
            let cat = entry.category.map { "[\($0)] " } ?? ""
            return "[\(ts)] \(entry.severity.uppercased()) \(cat)\(entry.source): \(entry.message)"
        }.joined(separator: "\n")
    }

    // MARK: - Clear

    public func clear() {
        entries.removeAll()
        persistToDisk()
    }

    public func clearSession() {
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
            if let handle = try? FileHandle(forWritingTo: logFileURL) {
                handle.seekToEndOfFile()
                handle.write((line + "\n").data(using: .utf8) ?? Data())
                handle.closeFile()
            } else {
                try? (line + "\n").write(to: logFileURL, atomically: true, encoding: .utf8)
            }
        }
        appendsSinceLastSizeCheck += 1
        if appendsSinceLastSizeCheck >= 200 {
            appendsSinceLastSizeCheck = 0
            rotateFileIfNeeded()
        }
    }

    private func rotateFileIfNeeded() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: logFileURL.path),
              let fileSize = attrs[.size] as? UInt64,
              fileSize > Self.maxFileSize else { return }
        persistToDisk()
    }

    private func persistToDisk() {
        let lines = entries.compactMap { entry -> String? in
            guard let data = try? JSONEncoder().encode(entry) else { return nil }
            return String(data: data, encoding: .utf8)
        }
        try? lines.joined(separator: "\n").write(to: logFileURL, atomically: true, encoding: .utf8)
    }

    /// Load entries from disk on startup
    public func loadFromDisk() {
        guard let content = try? String(contentsOf: logFileURL, encoding: .utf8) else { return }
        let decoder = JSONDecoder()
        let lines = content.components(separatedBy: "\n")
        for line in lines {
            guard !line.isEmpty, let data = line.data(using: .utf8),
                  let entry = try? decoder.decode(LogEntry.self, from: data) else { continue }
            entries.append(entry)
        }
        let trimmed = entries.count > maxEntries
        if trimmed {
            entries.removeFirst(entries.count - maxEntries)
        }
        if trimmed {
            persistToDisk()
        }
    }
}
