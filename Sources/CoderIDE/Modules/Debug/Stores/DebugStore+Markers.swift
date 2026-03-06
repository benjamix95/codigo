import Foundation

extension DebugStore {
    // MARK: - Debug Markers

    func addDebugMarker(_ marker: DebugMarker) {
        debugMarkers.append(marker)
    }

    func removeDebugMarker(id: UUID) {
        debugMarkers.removeAll { $0.id == id }
    }

    /// Number of files with debug markers
    var markedFileCount: Int {
        Set(debugMarkers.map(\.filePath)).count
    }

    /// Remove all debug markers from tracked files (revert lines)
    func cleanAllDebugMarkers() -> [(filePath: String, markers: [DebugMarker])] {
        let grouped = Dictionary(grouping: debugMarkers, by: \.filePath)
        let result = grouped.map { ($0.key, $0.value) }
        debugMarkers.removeAll()
        return result
    }

    // MARK: - Proceed / Fixed Flow

    func confirmReproduced() {
        userConfirmedReproduce = true
        phase = .fixing
        startNativeDebugSession()
        addLog(severity: .info, source: "debug_session", message: "Bug reproduced — proceeding to fix phase", category: "system")
    }

    /// Begin Mark Fixed in verifying phase. Returns the list of files expected to be cleaned.
    func beginMarkFixed(summary: String) -> [String] {
        let normalizedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingResolutionAfterClean = normalizedSummary.isEmpty ? "Debug session resolved" : normalizedSummary
        awaitingDebugClean = true
        phase = .verifying

        let files = Set(debugMarkers.map(\.filePath) + instrumentationPoints.map(\.filePath)).sorted()
        addLog(
            severity: .info,
            source: "debug_session",
            message: "Mark Fixed requested — waiting for debug_clean",
            detail: files.isEmpty ? nil : files.joined(separator: ", "),
            category: "system"
        )
        return files
    }

    func cancelPendingMarkFixed(reason: String? = nil) {
        guard awaitingDebugClean || pendingResolutionAfterClean != nil else { return }
        awaitingDebugClean = false
        pendingResolutionAfterClean = nil
        addLog(
            severity: .warning,
            source: "debug_session",
            message: "Mark Fixed aborted before cleanup started",
            detail: reason,
            category: "system"
        )
    }

    func resetLogFilters() {
        severityFilter = Set(DebugEntrySeverity.allCases)
        categoryFilter = nil
        searchQuery = ""
    }
}
