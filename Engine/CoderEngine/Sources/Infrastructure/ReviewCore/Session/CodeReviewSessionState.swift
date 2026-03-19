import Foundation

/// Coordinates exclusive file access between parallel swarms.
/// Uses exponential backoff with jitter to reduce contention and starvation.
/// Locks have a 10-minute lease; stale locks from crashed workers are auto-evicted.
public actor FileLockCoordinator {
    public init() {}

    private var lockedFiles: [String: String] = [:]
    private var lockTimestamps: [String: UInt64] = [:]
    private let maxLockLeaseNs: UInt64 = 600_000_000_000
    private var waitQueue: [String] = []
    private var waitingRequests: [String: Set<String>] = [:]
    private var waiterTimestamps: [String: UInt64] = [:]

    @discardableResult
    public func acquireLock(
        files: Set<String>,
        swarmId: String,
        isCancelled: (@Sendable () -> Bool)? = nil
    ) async -> Bool {
        guard !files.isEmpty else { return true }
        if !waitQueue.contains(swarmId) {
            waitQueue.append(swarmId)
            waiterTimestamps[swarmId] = DispatchTime.now().uptimeNanoseconds
        }
        waitingRequests[swarmId] = files

        let maxDuration: UInt64 = 300_000_000_000
        let startTime = DispatchTime.now().uptimeNanoseconds
        var backoffNs: UInt64 = 100_000_000

        while (DispatchTime.now().uptimeNanoseconds - startTime) < maxDuration {
            if isCancelled?() == true || Task.isCancelled {
                removeWaitingRequest(swarmId)
                return false
            }

            evictStaleLocks()
            let intersection = files.filter { lockedFiles[$0] != nil && lockedFiles[$0] != swarmId }
            let hasConflictingWaiterAhead = hasOverlappingWaiterAhead(of: swarmId, files: files)
            if intersection.isEmpty && !hasConflictingWaiterAhead {
                let now = DispatchTime.now().uptimeNanoseconds
                for file in files {
                    lockedFiles[file] = swarmId
                    lockTimestamps[file] = now
                }
                removeWaitingRequest(swarmId)
                return true
            }

            let jitter = UInt64.random(in: 0...(backoffNs / 4))
            try? await Task.sleep(nanoseconds: backoffNs + jitter)
            backoffNs = min(backoffNs * 2, 2_000_000_000)
        }

        removeWaitingRequest(swarmId)
        return false
    }

    public func releaseLock(files: Set<String>, swarmId: String) async {
        for file in files where lockedFiles[file] == swarmId {
            lockedFiles.removeValue(forKey: file)
            lockTimestamps.removeValue(forKey: file)
        }
    }

    public func releaseAllLocks(swarmId: String) {
        let removedFiles = lockedFiles.filter { $0.value == swarmId }.map(\.key)
        lockedFiles = lockedFiles.filter { $0.value != swarmId }
        for file in removedFiles {
            lockTimestamps.removeValue(forKey: file)
        }
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

    private func evictStaleLocks() {
        let now = DispatchTime.now().uptimeNanoseconds
        let staleFiles = lockTimestamps.filter { now - $0.value > maxLockLeaseNs }.map(\.key)
        for file in staleFiles {
            lockedFiles.removeValue(forKey: file)
            lockTimestamps.removeValue(forKey: file)
        }
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

extension CodeReviewSessionEvent {
    public static func findingFixApplied(findingId: String) -> CodeReviewSessionEvent {
        CodeReviewSessionEvent(
            type: .findingFixApplied,
            detail: "Fix applied for finding \(findingId)",
            metadata: ["finding_id": findingId]
        )
    }

    public static func patchPrepared(
        patchId: String,
        findingId: String
    ) -> CodeReviewSessionEvent {
        CodeReviewSessionEvent(
            type: .patchPrepared,
            detail: "Patch prepared for finding \(findingId)",
            metadata: ["patch_id": patchId, "finding_id": findingId]
        )
    }
}

// MARK: - CodeReviewSessionState

/// Thread-safe actor managing the state of a code review session.
/// Follows the DebugStore pattern but uses an actor for Sendable compliance
/// across CoderEngine (non-UI) boundaries.
public actor CodeReviewSessionState {
    enum SnapshotEmissionMode {
        case immediate
        case coalesced
    }

    // MARK: - Published State

    public let sessionId: String
    public let conversationId: UUID?
    var phase: ReviewSessionPhase = .idle
    var stage: ReviewSessionStage = .idle
    var findings: [CodeReviewFinding] = []
    var candidates: [ReviewCandidate] = []
    var patches: [ReviewPatchArtifact] = []
    var events: [CodeReviewSessionEvent] = []
    var config: SessionConfig
    var mutationSequence: UInt64 = 0
    var scope: ReviewSessionScope?
    var workspacePath: String?
    var currentRound: Int = 0
    var activeWorkerCount: Int = 0
    var startedAt: Date?
    var completedAt: Date?
    var analysisCompletedAt: Date?
    var lastError: String?
    var currentJobId: String?
    var lastTestStatus: ReviewSessionTestStatus?
    var audit: ReviewAuditSnapshot = .empty
    var outcome: ReviewSessionOutcome = .empty
    var phaseLedger: [ReviewPipelinePhaseLedgerEntry] = []
    var fileLedger: [ReviewPipelineFileLedgerEntry] = []

    /// Callback fired on every state mutation (for bridging to @MainActor stores).
    var onStateChange: (@Sendable (CodeReviewSessionSnapshot) -> Void)?
    private var pendingCoalescedNotificationTask: Task<Void, Never>?

    // MARK: - Init

    public init(
        sessionId: String = UUID().uuidString.lowercased(),
        conversationId: UUID? = nil,
        config: SessionConfig = .default,
        onStateChange: (@Sendable (CodeReviewSessionSnapshot) -> Void)? = nil
    ) {
        self.sessionId = sessionId
        self.conversationId = conversationId
        self.config = config
        self.onStateChange = onStateChange
    }

    // MARK: - Observation

    public func setOnStateChange(
        _ handler: @escaping @Sendable (CodeReviewSessionSnapshot) -> Void
    ) {
        onStateChange = handler
    }

    // MARK: - Snapshot

    public func snapshot() -> CodeReviewSessionSnapshot {
        CodeReviewSessionSnapshot(
            sessionId: sessionId,
            conversationId: conversationId,
            mutationSequence: mutationSequence,
            phase: phase,
            stage: stage,
            findings: findings,
            candidates: candidates,
            patches: patches,
            events: events,
            config: config,
            scope: scope,
            workspacePath: workspacePath,
            currentRound: currentRound,
            activeWorkerCount: activeWorkerCount,
            startedAt: startedAt,
            completedAt: completedAt,
            analysisCompletedAt: analysisCompletedAt,
            lastError: lastError,
            currentJobId: currentJobId,
            lastTestStatus: lastTestStatus,
            audit: audit,
            outcome: outcome,
            phaseLedger: phaseLedger,
            fileLedger: fileLedger,
            lastUpdatedAt: Date()
        )
    }

    public func replaceCanonicalSnapshot(_ snapshot: CodeReviewSessionSnapshot) {
        guard snapshot.sessionId == sessionId else { return }
        mutationSequence = snapshot.mutationSequence
        phase = snapshot.phase
        stage = snapshot.stage
        findings = snapshot.findings
        candidates = snapshot.candidates
        patches = snapshot.patches
        events = snapshot.events
        config = snapshot.config
        scope = snapshot.scope
        workspacePath = snapshot.workspacePath
        currentRound = snapshot.currentRound
        activeWorkerCount = snapshot.activeWorkerCount
        startedAt = snapshot.startedAt
        completedAt = snapshot.completedAt
        analysisCompletedAt = snapshot.analysisCompletedAt
        lastError = snapshot.lastError
        currentJobId = snapshot.currentJobId
        lastTestStatus = snapshot.lastTestStatus
        audit = snapshot.audit
        outcome = snapshot.outcome
        phaseLedger = snapshot.phaseLedger
        fileLedger = snapshot.fileLedger
        if let handler = onStateChange {
            Task { @MainActor in handler(snapshot) }
        }
    }

    // MARK: - Private

    /// Hard cap on events to prevent unbounded growth.
    private let eventsHardCap = 500
    private let coalescedNotificationDelayNanoseconds: UInt64 = 30_000_000

    func notifyChange(mode: SnapshotEmissionMode = .immediate) {
        if events.count > eventsHardCap {
            events = Array(events.suffix(eventsHardCap))
        }
        mutationSequence &+= 1
        switch mode {
        case .immediate:
            pendingCoalescedNotificationTask?.cancel()
            pendingCoalescedNotificationTask = nil
            emitSnapshot()
        case .coalesced:
            guard pendingCoalescedNotificationTask == nil else { return }
            pendingCoalescedNotificationTask = Task { [coalescedNotificationDelayNanoseconds] in
                try? await Task.sleep(nanoseconds: coalescedNotificationDelayNanoseconds)
                guard !Task.isCancelled else { return }
                self.flushCoalescedNotification()
            }
        }
    }

    private func flushCoalescedNotification() {
        pendingCoalescedNotificationTask = nil
        emitSnapshot()
    }

    private func emitSnapshot() {
        let snap = snapshot()
        if let handler = onStateChange {
            Task { @MainActor in handler(snap) }
        }
    }
}
