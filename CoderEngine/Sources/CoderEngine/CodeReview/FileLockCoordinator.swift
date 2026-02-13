import Foundation

/// Step di esecuzione ordinato per uno swarm
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

    /// Acquisisce lock sui file; blocca fino a disponibilità
    public func acquireLock(files: Set<String>, swarmId: String) async {
        guard !files.isEmpty else { return }
        while true {
            let intersection = files.filter { lockedFiles[$0] != nil && lockedFiles[$0] != swarmId }
            if intersection.isEmpty {
                for f in files {
                    lockedFiles[f] = swarmId
                }
                return
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    /// Rilascia lock
    public func releaseLock(files: Set<String>, swarmId: String) async {
        for f in files where lockedFiles[f] == swarmId {
            lockedFiles.removeValue(forKey: f)
        }
    }

    /// Pianifica l'ordine di esecuzione risolvendo conflitti su file condivisi
    public func planExecution(swarmFileClaims: [(swarmId: String, files: Set<String>)]) -> [ExecutionStep] {
        var steps: [ExecutionStep] = []
        var assigned: Set<String> = []
        var remaining = swarmFileClaims

        while !remaining.isEmpty {
            let available = remaining.filter { claim in
                claim.files.intersection(assigned).isEmpty
            }
            if let pick = available.first {
                steps.append(ExecutionStep(swarmId: pick.swarmId, files: pick.files))
                assigned.formUnion(pick.files)
                remaining.removeAll { $0.swarmId == pick.swarmId }
            } else {
                let pick = remaining.removeFirst()
                steps.append(ExecutionStep(swarmId: pick.swarmId, files: pick.files))
                assigned.formUnion(pick.files)
            }
        }
        return steps
    }
}
