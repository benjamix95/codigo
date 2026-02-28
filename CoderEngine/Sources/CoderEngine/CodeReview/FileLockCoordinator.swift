import Foundation

/// Coordina l'accesso esclusivo ai file tra swarm paralleli
public actor FileLockCoordinator {
    private var lockedFiles: [String: String] = [:]

    /// Acquires lock on files; blocks until available with a safety timeout.
    /// Accepts an optional cancellation check to exit the wait loop early.
    /// Returns `true` if locks were successfully acquired, `false` if cancelled or timed out.
    @discardableResult
    public func acquireLock(
        files: Set<String>,
        swarmId: String,
        isCancelled: (@Sendable () -> Bool)? = nil
    ) async -> Bool {
        guard !files.isEmpty else { return true }
        let maxAttempts = 1500 // ~5 minutes (1500 × 200ms)
        var attempt = 0
        while attempt < maxAttempts {
            if isCancelled?() == true { return false }
            let intersection = files.filter { lockedFiles[$0] != nil && lockedFiles[$0] != swarmId }
            if intersection.isEmpty {
                for f in files {
                    lockedFiles[f] = swarmId
                }
                return true
            }
            attempt += 1
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        // Timed out — do NOT force-acquire to avoid overwriting another swarm's lock
        return false
    }

    /// Rilascia lock
    public func releaseLock(files: Set<String>, swarmId: String) async {
        for f in files where lockedFiles[f] == swarmId {
            lockedFiles.removeValue(forKey: f)
        }
    }
}
