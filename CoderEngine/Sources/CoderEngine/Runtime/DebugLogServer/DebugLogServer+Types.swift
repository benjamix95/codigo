import Foundation

public extension DebugLogServer {
    struct LogEntry: Codable, Sendable {
        public let id: String
        public let timestamp: Date
        public let severity: String
        public let source: String
        public let message: String
        public let detail: String?
        public let category: String?
        public let sessionId: String?
        public let runId: String?
        public let hypothesisId: String?
        public let data: [String: String]?

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

    struct QueryResult: Sendable {
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
                    if String(entryHypothesis.prefix(8)) == short {
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
}
