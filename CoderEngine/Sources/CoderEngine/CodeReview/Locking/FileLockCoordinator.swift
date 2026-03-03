import Foundation

/// Coordinates exclusive file access between parallel swarms.
/// Uses exponential backoff with jitter to reduce contention and starvation.
/// Locks have a 10-minute lease — stale locks from crashed workers are auto-evicted.
public actor FileLockCoordinator {
    private var lockedFiles: [String: String] = [:]
    /// Timestamps tracking when each file was locked (for lease expiration).
    private var lockTimestamps: [String: UInt64] = [:]
    /// Maximum lock lease duration in nanoseconds (10 minutes).
    private let maxLockLeaseNs: UInt64 = 600_000_000_000
    /// FIFO queue for fairness: swarm IDs in order of first lock request
    private var waitQueue: [String] = []
    /// Pending file sets per waiting swarm (used to keep fairness for overlapping requests only).
    private var waitingRequests: [String: Set<String>] = [:]
    /// Timestamps for when each waiter entered the queue (for stale waiter eviction).
    private var waiterTimestamps: [String: UInt64] = [:]

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
            waiterTimestamps[swarmId] = DispatchTime.now().uptimeNanoseconds
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

            // Evict stale locks from crashed/timed-out workers
            evictStaleLocks()

            let intersection = files.filter { lockedFiles[$0] != nil && lockedFiles[$0] != swarmId }
            let hasConflictingWaiterAhead = hasOverlappingWaiterAhead(of: swarmId, files: files)
            if intersection.isEmpty && !hasConflictingWaiterAhead {
                // Allow parallelism for disjoint file sets, but preserve FIFO fairness
                // for swarms waiting on overlapping files.
                let now = DispatchTime.now().uptimeNanoseconds
                for f in files {
                    lockedFiles[f] = swarmId
                    lockTimestamps[f] = now
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
            lockTimestamps.removeValue(forKey: f)
        }
    }

    /// Releases ALL locks held by the specified swarm and removes it from the wait queue.
    /// Use this for cleanup on task cancellation or errors to prevent orphaned locks.
    public func releaseAllLocks(swarmId: String) {
        let removedFiles = lockedFiles.filter { $0.value == swarmId }.map(\.key)
        lockedFiles = lockedFiles.filter { $0.value != swarmId }
        for f in removedFiles { lockTimestamps.removeValue(forKey: f) }
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

    /// Evicts locks whose lease has expired (crashed/timed-out workers).
    /// Also cleans up stale waitQueue entries for swarms that have been waiting
    /// longer than the lease duration (phantom waiters from cancelled tasks).
    private func evictStaleLocks() {
        let now = DispatchTime.now().uptimeNanoseconds
        let staleFiles = lockTimestamps.filter { now - $0.value > maxLockLeaseNs }.map(\.key)
        for f in staleFiles {
            lockedFiles.removeValue(forKey: f)
            lockTimestamps.removeValue(forKey: f)
        }
        // Evict phantom waiters: swarms that have been in the wait queue longer
        // than the lease duration. This handles tasks cancelled externally without
        // calling releaseAllLocks, leaving ghost entries blocking fairness.
        let staleWaiters = waiterTimestamps.filter { now - $0.value > maxLockLeaseNs }.map(\.key)
        for swarmId in staleWaiters {
            removeWaitingRequest(swarmId)
        }
    }

    private func removeWaitingRequest(_ swarmId: String) {
        waitQueue.removeAll { $0 == swarmId }
        waitingRequests.removeValue(forKey: swarmId)
        waiterTimestamps.removeValue(forKey: swarmId)
    }
}
