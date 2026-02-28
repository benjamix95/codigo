import Foundation

/// Ordered execution step for a swarm
public struct ExecutionStep: Sendable {
    public let swarmId: String
    public let files: Set<String>

    public init(swarmId: String, files: Set<String>) {
        self.swarmId = swarmId
        self.files = files
    }
}

/// Coordina l'accesso esclusivo ai file tra swarm paralleli
public actor FileLockCoordinator {
    private var lockedFiles: [String: String] = [:]

    /// Acquires lock on files; blocks until available with a safety timeout.
    /// Accepts an optional cancellation check to exit the wait loop early.
    public func acquireLock(
        files: Set<String>,
        swarmId: String,
        isCancelled: (@Sendable () -> Bool)? = nil
    ) async {
        guard !files.isEmpty else { return }
        let maxAttempts = 1500 // ~5 minutes (1500 × 200ms)
        var attempt = 0
        while attempt < maxAttempts {
            if isCancelled?() == true { return }
            let intersection = files.filter { lockedFiles[$0] != nil && lockedFiles[$0] != swarmId }
            if intersection.isEmpty {
                for f in files {
                    lockedFiles[f] = swarmId
                }
                return
            }
            attempt += 1
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        for f in files {
            lockedFiles[f] = swarmId
        }
    }

    /// Rilascia lock
    public func releaseLock(files: Set<String>, swarmId: String) async {
        for f in files where lockedFiles[f] == swarmId {
            lockedFiles.removeValue(forKey: f)
        }
    }

    /// Plans execution order by resolving conflicts on shared files
    public func planExecution(swarmFileClaims: [(swarmId: String, files: Set<String>)]) -> [ExecutionStep] {
        var steps: [ExecutionStep] = []
        var remaining = swarmFileClaims

        while !remaining.isEmpty {
            var roundLockedFiles = Set<String>()
            var roundIndices: [Int] = []

            for (index, claim) in remaining.enumerated() {
                if claim.files.intersection(roundLockedFiles).isEmpty {
                    roundIndices.append(index)
                    roundLockedFiles.formUnion(claim.files)
                }
            }

            if roundIndices.isEmpty {
                let pick = remaining.removeFirst()
                steps.append(ExecutionStep(swarmId: pick.swarmId, files: pick.files))
                continue
            }

            // Collect steps before removal to preserve original order
            let roundSteps = roundIndices.map { remaining[$0] }
            for index in roundIndices.reversed() {
                remaining.remove(at: index)
            }
            for pick in roundSteps {
                steps.append(ExecutionStep(swarmId: pick.swarmId, files: pick.files))
            }
        }
        return steps
    }
}
