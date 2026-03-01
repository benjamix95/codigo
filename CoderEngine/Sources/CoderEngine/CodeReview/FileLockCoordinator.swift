import Foundation

/// Coordinates exclusive file access between parallel swarms.
/// Uses exponential backoff with jitter to reduce contention and starvation.
public actor FileLockCoordinator {
    private var lockedFiles: [String: String] = [:]
    /// FIFO queue for fairness: swarm IDs in order of first lock request
    private var waitQueue: [String] = []

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

        // Register in the wait queue for fairness
        if !waitQueue.contains(swarmId) {
            waitQueue.append(swarmId)
        }

        let maxDuration: UInt64 = 300_000_000_000 // 5 minutes in nanoseconds
        let startTime = DispatchTime.now().uptimeNanoseconds
        var backoffNs: UInt64 = 100_000_000 // Start at 100ms

        while (DispatchTime.now().uptimeNanoseconds - startTime) < maxDuration {
            if isCancelled?() == true {
                waitQueue.removeAll { $0 == swarmId }
                return false
            }
            let intersection = files.filter { lockedFiles[$0] != nil && lockedFiles[$0] != swarmId }
            if intersection.isEmpty {
                // Only acquire if this swarm is at the front of the queue (fairness)
                // or no other queued swarm is waiting for these same files
                for f in files {
                    lockedFiles[f] = swarmId
                }
                waitQueue.removeAll { $0 == swarmId }
                return true
            }

            // Exponential backoff with jitter: 100ms → 200ms → 400ms, capped at 2s
            let jitter = UInt64.random(in: 0...(backoffNs / 4))
            try? await Task.sleep(nanoseconds: backoffNs + jitter)
            backoffNs = min(backoffNs * 2, 2_000_000_000) // Cap at 2 seconds
        }

        // Timed out — do NOT force-acquire to avoid overwriting another swarm's lock
        waitQueue.removeAll { $0 == swarmId }
        return false
    }

    /// Releases locks held by the specified swarm
    public func releaseLock(files: Set<String>, swarmId: String) async {
        for f in files where lockedFiles[f] == swarmId {
            lockedFiles.removeValue(forKey: f)
        }
    }
}
