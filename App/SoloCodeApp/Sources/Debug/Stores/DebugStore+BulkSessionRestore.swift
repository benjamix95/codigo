import Foundation

extension DebugStore {
    /// Dopo `restore(from:)` o altre ricostruzioni bulk di `flow` / `session` (senza passare dai setter),
    /// riallinea monitor log e task watchdog.
    ///
    /// Estendi qui se aggiungi nuovi timer correlati alla sessione debug non coperti da proprietà dedicate.
    func reconcileWatchdogAndLogMonitorAfterBulkSessionRestore() {
        if awaitingDebugClean {
            scheduleDebugCleanFallbackIfNeeded()
        }
        guard flow.phase != .idle else { return }
        startLogFileMonitor(path: activeDebugLogPath)
        rescheduleDebugIdleWarningIfNeeded()
    }
}
