import Foundation

public struct ProcessLifecycleMetrics: Codable, Equatable, Sendable {
    public let startedAt: Date
    public let finishedAt: Date
    public let durationMs: Int
    public let timedOut: Bool
    public let terminatedBySupervisor: Bool
    public let stdoutBytes: Int
    public let stderrBytes: Int

    public init(
        startedAt: Date,
        finishedAt: Date,
        durationMs: Int,
        timedOut: Bool,
        terminatedBySupervisor: Bool,
        stdoutBytes: Int,
        stderrBytes: Int
    ) {
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.durationMs = durationMs
        self.timedOut = timedOut
        self.terminatedBySupervisor = terminatedBySupervisor
        self.stdoutBytes = stdoutBytes
        self.stderrBytes = stderrBytes
    }
}
