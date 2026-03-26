import Foundation

extension DebugStore {
    /// Seconds to wait for `debug_clean` after Mark Fixed before failing open.
    static var debugCleanFallbackSeconds: UInt64 { 120 }

    /// Inactivity warning while phase stays active (no automatic phase change).
    static var sessionIdleLogWarningSeconds: UInt64 { 900 }

    func cancelDebugSessionWatchdogTasks() {
        debugCleanAwaitingTask?.cancel()
        debugCleanAwaitingTask = nil
        sessionIdleWarningTask?.cancel()
        sessionIdleWarningTask = nil
    }

    func scheduleDebugCleanFallbackIfNeeded() {
        debugCleanAwaitingTask?.cancel()
        guard awaitingDebugClean else { return }
        let nanos = Self.debugCleanFallbackSeconds * 1_000_000_000
        debugCleanAwaitingTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: nanos)
            guard let self, !Task.isCancelled else { return }
            guard self.awaitingDebugClean else { return }
            self.addLog(
                severity: .warning,
                source: "debug_session",
                message: "Timeout waiting for debug_clean — releasing Mark Fixed wait.",
                category: "system"
            )
            self.applyDebugCleanResult(
                success: false,
                detail: "Timed out waiting for agent debug_clean event."
            )
        }
    }

    func rescheduleDebugIdleWarningIfNeeded() {
        sessionIdleWarningTask?.cancel()
        sessionIdleWarningTask = nil
        guard phase.isActive, phase != .resolved else { return }
        let nanos = Self.sessionIdleLogWarningSeconds * 1_000_000_000
        sessionIdleWarningTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: nanos)
            guard let self, !Task.isCancelled else { return }
            guard self.phase.isActive, self.phase != .resolved, self.phase != .idle else { return }
            self.addLog(
                severity: .warning,
                source: "debug_session",
                message: "Debug session idle for a long time. If the agent stalled, stop or resolve manually.",
                category: "system"
            )
            self.rescheduleDebugIdleWarningIfNeeded()
        }
    }
}
