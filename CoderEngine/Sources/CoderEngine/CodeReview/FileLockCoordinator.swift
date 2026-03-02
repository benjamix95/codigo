import Foundation

/// Coordinates exclusive file access between parallel swarms.
/// Uses exponential backoff with jitter to reduce contention and starvation.
public actor FileLockCoordinator {
    private var lockedFiles: [String: String] = [:]
    /// FIFO queue for fairness: swarm IDs in order of first lock request
    private var waitQueue: [String] = []
    /// Pending file sets per waiting swarm (used to keep fairness for overlapping requests only).
    private var waitingRequests: [String: Set<String>] = [:]

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
        waitingRequests[swarmId] = files

        let maxDuration: UInt64 = 300_000_000_000 // 5 minutes in nanoseconds
        let startTime = DispatchTime.now().uptimeNanoseconds
        var backoffNs: UInt64 = 100_000_000 // Start at 100ms

        while (DispatchTime.now().uptimeNanoseconds - startTime) < maxDuration {
            if isCancelled?() == true || Task.isCancelled {
                removeWaitingRequest(swarmId)
                return false
            }

            let intersection = files.filter { lockedFiles[$0] != nil && lockedFiles[$0] != swarmId }
            let hasConflictingWaiterAhead = hasOverlappingWaiterAhead(of: swarmId, files: files)
            if intersection.isEmpty && !hasConflictingWaiterAhead {
                // Allow parallelism for disjoint file sets, but preserve FIFO fairness
                // for swarms waiting on overlapping files.
                for f in files {
                    lockedFiles[f] = swarmId
                }
                removeWaitingRequest(swarmId)
                return true
            }

            // Exponential backoff with jitter: 100ms → 200ms → 400ms, capped at 2s
            let jitter = UInt64.random(in: 0...(backoffNs / 4))
            try? await Task.sleep(nanoseconds: backoffNs + jitter)
            backoffNs = min(backoffNs * 2, 2_000_000_000) // Cap at 2 seconds
        }

        // Timed out — do NOT force-acquire to avoid overwriting another swarm's lock
        removeWaitingRequest(swarmId)
        return false
    }

    /// Releases locks held by the specified swarm
    public func releaseLock(files: Set<String>, swarmId: String) async {
        for f in files where lockedFiles[f] == swarmId {
            lockedFiles.removeValue(forKey: f)
        }
    }

    /// Releases ALL locks held by the specified swarm and removes it from the wait queue.
    /// Use this for cleanup on task cancellation or errors to prevent orphaned locks.
    public func releaseAllLocks(swarmId: String) {
        lockedFiles = lockedFiles.filter { $0.value != swarmId }
        removeWaitingRequest(swarmId)
    }

    private func hasOverlappingWaiterAhead(of swarmId: String, files: Set<String>) -> Bool {
        for queuedSwarmId in waitQueue {
            if queuedSwarmId == swarmId {
                return false
            }
            guard let queuedFiles = waitingRequests[queuedSwarmId] else {
                continue
            }
            if !queuedFiles.isDisjoint(with: files) {
                return true
            }
        }
        return false
    }

    private func removeWaitingRequest(_ swarmId: String) {
        waitQueue.removeAll { $0 == swarmId }
        waitingRequests.removeValue(forKey: swarmId)
    }
}
