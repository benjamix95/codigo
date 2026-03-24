import Foundation

// MARK: - BackpressureSignal

/// Segnali di backpressure riconosciuti dallo scheduler (§11.3).
public enum BackpressureSignal: String, Sendable, Equatable, CaseIterable {
    case workerQueueFull = "worker_queue_full"
    case providerRateLimited = "provider_rate_limited"
    case memoryPressure = "memory_pressure"
    case swarmBudgetExhausted = "swarm_budget_exhausted"
}

// MARK: - BackpressurePolicy

/// Policy applicata quando si attiva un segnale di backpressure.
public struct BackpressurePolicy: Sendable, Equatable {
    /// Se true, lo scheduler sospende l'estrazione di nuovi task dal DAG.
    public let pauseScheduling: Bool
    /// Riduzione temporanea del max_workers (0 = nessuna riduzione).
    public let workerReduction: Int
    /// Delay aggiuntivo tra iterazioni scheduler (ms).
    public let throttleDelayMs: Int

    public init(
        pauseScheduling: Bool = false,
        workerReduction: Int = 0,
        throttleDelayMs: Int = 0
    ) {
        self.pauseScheduling = pauseScheduling
        self.workerReduction = workerReduction
        self.throttleDelayMs = throttleDelayMs
    }
}

// MARK: - BackpressureController

/// Gestisce i segnali di backpressure e le policy associate (§11.3).
///
/// Lo scheduler consulta il controller prima di ogni dispatch
/// per verificare se ci sono segnali attivi che richiedono rallentamento.
public actor BackpressureController {

    private var activeSignals: Set<BackpressureSignal> = []
    private var policies: [BackpressureSignal: BackpressurePolicy]
    private var signalHistory: [(signal: BackpressureSignal, activated: Bool, timestamp: Date)] = []
    private let maxSignalHistorySize: Int = 1000
    private let autoDeactivateTimeoutMs: Int = 300_000

    /// Quante volte è stato attivato backpressure in totale.
    private(set) var totalActivations: Int = 0

    public init(policies: [BackpressureSignal: BackpressurePolicy]? = nil) {
        self.policies = policies ?? Self.defaultPolicies
    }

    // MARK: - Signal Management

    /// Attiva un segnale di backpressure.
    public func activate(_ signal: BackpressureSignal) {
        let isNew = activeSignals.insert(signal).inserted
        if isNew {
            totalActivations += 1
            signalHistory.append((signal, true, Date()))
            trimSignalHistoryIfNeeded()
        }
    }

    /// Disattiva un segnale di backpressure.
    public func deactivate(_ signal: BackpressureSignal) {
        let removed = activeSignals.remove(signal)
        if removed != nil {
            signalHistory.append((signal, false, Date()))
            trimSignalHistoryIfNeeded()
        }
    }

    // MARK: - Query

    /// True se almeno un segnale è attivo.
    public var isActive: Bool {
        !activeSignals.isEmpty
    }

    /// True se lo scheduling deve essere sospeso.
    public var shouldPauseScheduling: Bool {
        activeSignals.contains { signal in
            policies[signal]?.pauseScheduling == true
        }
    }

    /// Riduzione totale dei worker dalla somma di tutte le policy attive.
    public var totalWorkerReduction: Int {
        activeSignals.reduce(0) { sum, signal in
            sum + (policies[signal]?.workerReduction ?? 0)
        }
    }

    /// Delay massimo di throttle tra le policy attive.
    public var maxThrottleDelayMs: Int {
        activeSignals.reduce(0) { maxVal, signal in
            max(maxVal, policies[signal]?.throttleDelayMs ?? 0)
        }
    }

    /// Segnali attualmente attivi.
    public var currentSignals: Set<BackpressureSignal> {
        activeSignals
    }

    /// Effective max workers tenendo conto della backpressure.
    public func effectiveMaxWorkers(base: Int) -> Int {
        max(1, base - totalWorkerReduction)
    }

    // MARK: - History Maintenance

    /// Mantiene signalHistory entro il limite massimo.
    private func trimSignalHistoryIfNeeded() {
        if signalHistory.count > maxSignalHistorySize {
            let excess = signalHistory.count - maxSignalHistorySize
            signalHistory.removeFirst(excess)
        }
    }

    /// Disattiva segnali rimasti attivi oltre il timeout (segnali bloccati).
    public func pruneStaleSignals() {
        let now = Date()
        let timeoutSeconds = Double(autoDeactivateTimeoutMs) / 1000.0
        var staleSignals: [BackpressureSignal] = []

        for signal in activeSignals {
            // Trova l'ultima attivazione per questo segnale
            if let lastActivation = signalHistory.last(where: { $0.signal == signal && $0.activated }) {
                if now.timeIntervalSince(lastActivation.timestamp) > timeoutSeconds {
                    staleSignals.append(signal)
                }
            }
        }

        for signal in staleSignals {
            NSLog("[BackpressureController] auto-deactivating stale signal: %@", signal.rawValue)
            activeSignals.remove(signal)
            signalHistory.append((signal, false, now))
            trimSignalHistoryIfNeeded()
        }
    }

    // MARK: - Reset

    public func reset() {
        activeSignals.removeAll()
        signalHistory.removeAll()
        totalActivations = 0
    }

    // MARK: - Default Policies

    static let defaultPolicies: [BackpressureSignal: BackpressurePolicy] = [
        .workerQueueFull: BackpressurePolicy(
            pauseScheduling: true,
            workerReduction: 0,
            throttleDelayMs: 500
        ),
        .providerRateLimited: BackpressurePolicy(
            pauseScheduling: false,
            workerReduction: 1,
            throttleDelayMs: 2000
        ),
        .memoryPressure: BackpressurePolicy(
            pauseScheduling: false,
            workerReduction: 2,
            throttleDelayMs: 1000
        ),
        .swarmBudgetExhausted: BackpressurePolicy(
            pauseScheduling: true,
            workerReduction: 0,
            throttleDelayMs: 1000
        )
    ]
}
