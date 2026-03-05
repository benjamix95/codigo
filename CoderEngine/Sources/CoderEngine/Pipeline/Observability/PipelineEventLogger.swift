import Foundation

// MARK: - PipelineEventLoggerError

public enum PipelineEventLoggerError: Error, Sendable, Equatable {
    case alreadyShutdown
    case invalidEntry(reason: String)
    case sequenceOutOfOrder(expected: UInt64, got: UInt64)
}

// MARK: - PipelineEventLoggerProtocol

public protocol PipelineEventLoggerProtocol: Sendable {
    func append(_ entry: EventLogEntry) async throws
    func entries(forJob jobId: String) async -> [EventLogEntry]
    func allEntries() async -> [EventLogEntry]
    func currentSequence() async -> UInt64
    func shutdown() async
}

// MARK: - PipelineEventLogger

/// Logger append-only per eventi della pipeline (§6.7, §18).
///
/// Vincoli:
/// - `sequence_number` MUST essere monotonicamente crescente per job
/// - Ogni entry MUST includere `job_id`, `phase`, `event`
/// - `correlation_id` MUST restare stabile lungo la catena causale
public actor PipelineEventLogger: PipelineEventLoggerProtocol {

    private var log: [EventLogEntry] = []
    private var sequenceCounter: UInt64 = 0
    private var isShutdown = false

    /// Contatori per sequenze per-job (§6.7 monotonic guarantee).
    private var jobSequences: [String: UInt64] = [:]

    public init() {}

    // MARK: - Append

    public func append(_ entry: EventLogEntry) async throws {
        guard !isShutdown else {
            throw PipelineEventLoggerError.alreadyShutdown
        }
        try entry.validate()

        sequenceCounter += 1
        let jobSeq = (jobSequences[entry.jobId] ?? 0) + 1
        jobSequences[entry.jobId] = jobSeq

        var enriched = entry
        enriched.sequenceNumber = sequenceCounter
        log.append(enriched)
    }

    // MARK: - Query

    public func entries(forJob jobId: String) async -> [EventLogEntry] {
        log.filter { $0.jobId == jobId }
    }

    public func allEntries() async -> [EventLogEntry] {
        log
    }

    public func currentSequence() async -> UInt64 {
        sequenceCounter
    }

    public func entryCount() -> Int {
        log.count
    }

    public func jobSequence(for jobId: String) -> UInt64 {
        jobSequences[jobId] ?? 0
    }

    // MARK: - NDJSON Export

    /// Serializza tutte le entries in formato NDJSON (§6.7).
    public func exportNDJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var lines: [Data] = []
        for entry in log {
            let line = try encoder.encode(entry)
            lines.append(line)
        }
        let newline = Data("\n".utf8)
        var result = Data()
        for (i, line) in lines.enumerated() {
            result.append(line)
            if i < lines.count - 1 {
                result.append(newline)
            }
        }
        return result
    }

    // MARK: - Lifecycle

    public func shutdown() async {
        isShutdown = true
    }

    public func reset() {
        log.removeAll()
        jobSequences.removeAll()
        sequenceCounter = 0
        isShutdown = false
    }
}
