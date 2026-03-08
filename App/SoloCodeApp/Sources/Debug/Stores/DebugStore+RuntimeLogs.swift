extension DebugStore {
    // MARK: - Runtime Log Management

    func addRuntimeLog(_ entry: RuntimeLogEntry) {
        runtimeLogs.append(entry)
        if runtimeLogs.count > 2000 {
            runtimeLogs.removeFirst(runtimeLogs.count - 2000)
        }
    }

    func addRuntimeLog(
        location: String,
        message: String,
        data: [String: String] = [:],
        hypothesisId: String? = nil,
        runId: String? = nil
    ) {
        let normalizedRunId = runId?.trimmingCharacters(in: .whitespacesAndNewlines)
        addRuntimeLog(RuntimeLogEntry(
            location: location,
            message: message,
            data: data,
            runId: (normalizedRunId?.isEmpty == false) ? normalizedRunId : currentRunId,
            hypothesisId: hypothesisId
        ))
    }

    /// Runtime logs for the current run (filtered by runId)
    var currentRunLogs: [RuntimeLogEntry] {
        guard let runId = currentRunId else { return runtimeLogs }
        return runtimeLogs.filter { $0.runId == runId }
    }

    /// Runtime logs linked to a specific hypothesis
    func runtimeLogs(for hypothesisId: String) -> [RuntimeLogEntry] {
        runtimeLogs.filter { $0.hypothesisId == hypothesisId }
    }

    func clearRuntimeLogs() {
        runtimeLogs.removeAll()
    }
}

