import Foundation

// MARK: - DeadLetterReason

/// Motivo per cui un evento è finito nella DLQ (§6.9).
public enum DeadLetterReason: Sendable, Equatable, CustomStringConvertible {
    case maxAttemptsExceeded(Int)
    case noSubscribers
    case handlerError(String)
    case invalidEvent(String)

    public var description: String {
        switch self {
        case .maxAttemptsExceeded(let n):
            "max_attempts_exceeded(\(n))"
        case .noSubscribers:
            "no_subscribers"
        case .handlerError(let msg):
            "handler_error: \(msg)"
        case .invalidEvent(let msg):
            "invalid_event: \(msg)"
        }
    }
}

// MARK: - DeadLetterEntry

/// Singola entry nella dead letter queue.
public struct DeadLetterEntry: Sendable {
    public let event: EventBusEvent
    public let reason: DeadLetterReason
    public let enqueuedAt: Date
    public let originalDeliveryAttempts: Int

    public init(
        event: EventBusEvent,
        reason: DeadLetterReason,
        enqueuedAt: Date = Date(),
        originalDeliveryAttempts: Int
    ) {
        self.event = event
        self.reason = reason
        self.enqueuedAt = enqueuedAt
        self.originalDeliveryAttempts = originalDeliveryAttempts
    }
}

// MARK: - DLQAlert

/// Alert emesso quando la DLQ supera una soglia.
public struct DLQAlert: Sendable {
    public let timestamp: Date
    public let currentSize: Int
    public let threshold: Int
    public let message: String

    public init(
        timestamp: Date = Date(),
        currentSize: Int,
        threshold: Int,
        message: String
    ) {
        self.timestamp = timestamp
        self.currentSize = currentSize
        self.threshold = threshold
        self.message = message
    }
}

// MARK: - DLQAlertHandler

/// Callback invocato quando la DLQ genera un alert.
public typealias DLQAlertHandler = @Sendable (DLQAlert) async -> Void

// MARK: - DeadLetterQueue

/// Dead letter queue per eventi non consegnabili (§6.9).
///
/// Responsabilità:
/// - Accumula eventi che hanno superato il max delivery attempts
/// - Accumula eventi senza subscriber (unroutable)
/// - Alerting quando la coda supera soglie configurabili
/// - Query per ispezione e replay manuale
/// - Bounded capacity con drop dei più vecchi (FIFO eviction)
public actor DeadLetterQueue {

    // MARK: - Configuration

    public let capacity: Int
    public let alertThreshold: Int

    // MARK: - State

    private var entries: [DeadLetterEntry] = []
    private var alertHandler: DLQAlertHandler?
    private var alertsFired: Int = 0

    // MARK: - Metrics

    private(set) var totalEnqueued: Int = 0
    private(set) var totalEvicted: Int = 0
    private var reasonCounts: [String: Int] = [:]

    // MARK: - Init

    /// - Parameters:
    ///   - capacity: Massimo numero di entry. Default 1000.
    ///   - alertThreshold: Soglia per emissione alert. Default 80% della capacity.
    public init(capacity: Int = 1000, alertThreshold: Int? = nil) {
        self.capacity = max(1, capacity)
        self.alertThreshold = alertThreshold ?? max(1, capacity * 80 / 100)
    }

    // MARK: - Enqueue

    /// Aggiunge un evento alla DLQ.
    /// Se la coda è piena, evict il più vecchio (FIFO).
    public func enqueue(
        _ event: EventBusEvent,
        reason: DeadLetterReason
    ) async {
        if entries.count >= capacity {
            entries.removeFirst()
            totalEvicted += 1
        }

        let entry = DeadLetterEntry(
            event: event,
            reason: reason,
            originalDeliveryAttempts: event.deliveryAttempts
        )
        entries.append(entry)
        totalEnqueued += 1

        let reasonKey = String(describing: reason).components(separatedBy: "(").first ?? "unknown"
        reasonCounts[reasonKey, default: 0] += 1

        if entries.count >= alertThreshold {
            await fireAlert()
        }
    }

    // MARK: - Alert

    /// Configura l'handler per gli alert DLQ.
    public func onAlert(_ handler: @escaping DLQAlertHandler) {
        self.alertHandler = handler
    }

    private func fireAlert() async {
        alertsFired += 1
        let alert = DLQAlert(
            currentSize: entries.count,
            threshold: alertThreshold,
            message: "DLQ size \(entries.count) >= threshold \(alertThreshold)"
        )
        await alertHandler?(alert)
    }

    // MARK: - Query

    public func count() -> Int {
        entries.count
    }

    /// Restituisce le entry più recenti.
    public func recent(limit: Int = 20) -> [DeadLetterEntry] {
        Array(entries.suffix(limit))
    }

    /// Restituisce tutte le entry per un dato job.
    public func entriesForJob(_ jobId: String) -> [DeadLetterEntry] {
        entries.filter { $0.event.jobId == jobId }
    }

    /// Restituisce le entry filtrate per reason.
    public func entriesByReason(_ reason: String) -> [DeadLetterEntry] {
        entries.filter {
            String(describing: $0.reason).hasPrefix(reason)
        }
    }

    // MARK: - Drain / Retry

    /// Rimuove e restituisce tutte le entry (per retry manuale).
    public func drain() -> [DeadLetterEntry] {
        let drained = entries
        entries.removeAll()
        return drained
    }

    /// Rimuove e restituisce entry per un job specifico.
    public func drainJob(_ jobId: String) -> [DeadLetterEntry] {
        let matching = entries.filter { $0.event.jobId == jobId }
        entries.removeAll { $0.event.jobId == jobId }
        return matching
    }

    // MARK: - Metrics

    /// Breakdown dei motivi DLQ.
    public func reasonBreakdown() -> [String: Int] {
        reasonCounts
    }

    /// Numero totale di alert emessi.
    public func alertCount() -> Int {
        alertsFired
    }

    // MARK: - Reset

    public func reset() {
        entries.removeAll()
        totalEnqueued = 0
        totalEvicted = 0
        reasonCounts.removeAll()
        alertsFired = 0
    }
}
