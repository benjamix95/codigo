extension DebugStore {
    // MARK: - Log Management

    func addLog(_ entry: DebugLogEntry) {
        logs.append(entry)
        // Keep last 2000 entries
        if logs.count > 2000 {
            logs.removeFirst(logs.count - 2000)
        }
    }

    func addLog(severity: DebugEntrySeverity, source: String, message: String, detail: String? = nil, category: String? = nil) {
        addLog(DebugLogEntry(severity: severity, source: source, message: message, detail: detail, category: category))
    }

    func clearLogs() {
        logs.removeAll()
    }
}

