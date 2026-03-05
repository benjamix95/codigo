import Foundation

// MARK: - JobStateMachineError

public enum JobStateMachineError: Error, Sendable, Equatable {
    case invalidTransition(from: JobState, to: JobState)
    case jobAlreadyTerminal(state: JobState)
    case rollbackTimeout(elapsedMs: Int)
}

// MARK: - StateTransitionRecord

/// Record di ogni transizione di stato (§5.3 invariante 2).
public struct StateTransitionRecord: Sendable, Equatable {
    public let from: JobState
    public let to: JobState
    public let timestamp: Date
    public let reason: String?

    public init(from: JobState, to: JobState, timestamp: Date = Date(), reason: String? = nil) {
        self.from = from
        self.to = to
        self.timestamp = timestamp
        self.reason = reason
    }
}

// MARK: - JobStateMachineDelegate

/// Protocollo delegate per notificare transizioni di stato all'orchestrator.
public protocol JobStateMachineDelegate: AnyObject, Sendable {
    func stateMachine(
        _ sm: JobStateMachine,
        didTransition record: StateTransitionRecord,
        job: PipelineJob
    ) async
}

// MARK: - JobStateMachine

/// State machine del job pipeline (§5.3).
///
/// Responsabilità:
/// - Validazione transizioni di stato
/// - Registrazione storico transizioni
/// - Notifica delegate (orchestrator) per emissione eventi
/// - Enforcement invarianti (terminal check, rolling_back timeout)
public actor JobStateMachine {

    private(set) var job: PipelineJob
    private(set) var transitionHistory: [StateTransitionRecord] = []
    private var rollingBackStartedAt: Date?

    public weak var delegate: JobStateMachineDelegate?

    /// Timeout massimo per stato rolling_back (§5.3 invariante 4).
    public let rollingBackTimeoutMs: Int

    public init(
        job: PipelineJob,
        rollingBackTimeoutMs: Int = 10_000
    ) {
        self.job = job
        self.rollingBackTimeoutMs = rollingBackTimeoutMs
    }

    // MARK: - Transition

    /// Esegue una transizione di stato validata.
    /// Lancia `JobStateMachineError` se la transizione è illegale.
    @discardableResult
    public func transition(
        to newState: JobState,
        reason: String? = nil
    ) async throws -> StateTransitionRecord {
        let current = job.state

        guard !current.isTerminal else {
            throw JobStateMachineError.jobAlreadyTerminal(state: current)
        }

        guard current.canTransition(to: newState) else {
            throw JobStateMachineError.invalidTransition(from: current, to: newState)
        }

        if newState == .rollingBack {
            rollingBackStartedAt = Date()
        }

        if current == .rollingBack {
            rollingBackStartedAt = nil
        }

        let record = StateTransitionRecord(
            from: current,
            to: newState,
            reason: reason
        )
        transitionHistory.append(record)
        job.state = newState

        await delegate?.stateMachine(self, didTransition: record, job: job)

        return record
    }

    // MARK: - Query

    public var currentState: JobState {
        job.state
    }

    public var isTerminal: Bool {
        job.state.isTerminal
    }

    public var history: [StateTransitionRecord] {
        transitionHistory
    }

    /// Verifica se rolling_back ha superato il timeout (§5.3 invariante 4).
    public func checkRollingBackTimeout() throws {
        guard job.state == .rollingBack, let started = rollingBackStartedAt else {
            return
        }
        let elapsedMs = Int(Date().timeIntervalSince(started) * 1000)
        if elapsedMs > rollingBackTimeoutMs {
            throw JobStateMachineError.rollbackTimeout(elapsedMs: elapsedMs)
        }
    }

    // MARK: - Convenience

    /// Tenta abort con reason.
    public func abort(reason: String) async throws {
        let current = job.state
        if current == .failed {
            try await transition(to: .aborted, reason: reason)
        } else if current == .circuitBroken {
            try await transition(to: .aborted, reason: reason)
        } else if !current.isTerminal {
            if current.canTransition(to: .failed) {
                try await transition(to: .failed, reason: reason)
                try await transition(to: .aborted, reason: reason)
            } else if current == .failed || current.canTransition(to: .aborted) {
                try await transition(to: .aborted, reason: reason)
            }
        }
    }

    /// Reset per testing.
    public func reset(to state: JobState = .intake) {
        job.state = state
        transitionHistory.removeAll()
        rollingBackStartedAt = nil
    }
}
