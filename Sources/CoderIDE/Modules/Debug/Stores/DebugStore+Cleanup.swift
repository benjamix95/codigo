extension DebugStore {
    /// Apply debug_clean result; resolve only when cleanup succeeds.
    func applyDebugCleanResult(success: Bool, detail: String?) {
        guard awaitingDebugClean else { return }

        if success {
            _ = cleanAllDebugMarkers()
            _ = cleanAllInstrumentation()
            let summary = pendingResolutionAfterClean ?? resolutionSummary
            resolveSession(summary: summary.isEmpty ? "Debug session resolved" : summary)
            if let detail, !detail.isEmpty {
                addLog(severity: .info, source: "debug_clean", message: detail, category: "system")
            }
        } else {
            awaitingDebugClean = false
            pendingResolutionAfterClean = nil
            phase = .verifying
            addLog(
                severity: .warning,
                source: "debug_clean",
                message: "debug_clean failed; session remains in verifying",
                detail: detail,
                category: "system"
            )
        }
    }

    /// Backward-compatible helper (legacy flow). Prefer beginMarkFixed + applyDebugCleanResult.
    func markFixed(summary: String) -> (markers: [(filePath: String, markers: [DebugMarker])], instrumentation: [InstrumentationPoint]) {
        let markers = cleanAllDebugMarkers()
        let instrumentation = cleanAllInstrumentation()
        resolveSession(summary: summary)
        return (markers, instrumentation)
    }
}

