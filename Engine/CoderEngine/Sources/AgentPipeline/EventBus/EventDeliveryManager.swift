import Foundation

// MARK: - DeliveryAttempt

/// Risultato di un tentativo di consegna.
public struct DeliveryAttempt: Sendable {
    public let eventId: String
    public let subscriptionId: String
    public let attemptNumber: Int
    public let success: Bool
    public let error: String?
    public let timestamp: Date

    public init(
        eventId: String,
        subscriptionId: String,
        attemptNumber: Int,
        success: Bool,
        error: String? = nil,
        timestamp: Date = Date()
    ) {
        self.eventId = eventId
        self.subscriptionId = subscriptionId
        self.attemptNumber = attemptNumber
        self.success = success
        self.error = error
        self.timestamp = timestamp
    }
}

// MARK: - DeliveryRecord

/// Record interno che traccia lo stato di consegna di un evento
/// verso un singolo subscriber.
struct DeliveryRecord: Sendable {
    var event: EventBusEvent
    let subscription: EventSubscription
    var attempts: Int
    var lastAttemptAt: Date?
    var lastError: String?
}

// MARK: - EventDeliveryManager

/// Gestisce la consegna at-least-once degli eventi ai subscriber (§6.9).
///
/// Responsabilità:
/// - Consegna con retry (exponential backoff + jitter deterministico)
/// - Tracciamento tentativi per evento/subscriber
/// - Inoltro a DLQ dopo `maxAttempts` fallimenti
/// - Metriche di delivery (successi, fallimenti, pending)
public actor EventDeliveryManager {

    // MARK: - Configuration

    /// Numero massimo di tentativi prima di DLQ.
    public let maxAttempts: Int

    /// Base delay in millisecondi per backoff.
    public let baseDelayMs: UInt64

    /// Delay massimo in millisecondi.
    public let maxDelayMs: UInt64

    /// Numero massimo di delivery attempt conservati in memoria.
    public let maxAttemptLogEntries: Int

    /// Timeout in millisecondi per singola delivery.
    public let deliveryTimeoutMs: UInt64

    // MARK: - State

    private var pendingRecords: [String: DeliveryRecord] = [:]
    private var attemptLog: [DeliveryAttempt] = []
    private var deliveryTasks: [String: Task<Void, Never>] = [:]
    private let deadLetterQueue: DeadLetterQueue

    // MARK: - Metrics

    private(set) var totalDelivered: Int = 0
    private(set) var totalFailed: Int = 0

    // MARK: - Init

    public init(
        maxAttempts: Int = 3,
        baseDelayMs: UInt64 = 100,
        maxDelayMs: UInt64 = 5000,
        maxAttemptLogEntries: Int = 500,
        deliveryTimeoutMs: UInt64 = 30_000,
        deadLetterQueue: DeadLetterQueue
    ) {
        self.maxAttempts = max(1, maxAttempts)
        self.baseDelayMs = baseDelayMs
        self.maxDelayMs = maxDelayMs
        self.maxAttemptLogEntries = max(1, maxAttemptLogEntries)
        self.deliveryTimeoutMs = deliveryTimeoutMs
        self.deadLetterQueue = deadLetterQueue
    }

    // MARK: - Deliver

    /// Consegna un evento a un subscriber con at-least-once semantics.
    public func deliver(
        event: EventBusEvent,
        to subscription: EventSubscription
    ) async {
        let recordKey = "\(event.eventId)_\(subscription.id)"
        pendingRecords[recordKey] = DeliveryRecord(
            event: event,
            subscription: subscription,
            attempts: 0,
            lastAttemptAt: nil,
            lastError: nil
        )
        guard deliveryTasks[recordKey] == nil else { return }
        deliveryTasks[recordKey] = Task { [recordKey] in
            await self.processDelivery(recordKey: recordKey)
        }
    }

    // MARK: - Attempt

    /// Esegue un singolo tentativo di consegna.
    /// Cattura qualsiasi errore dal handler e lo converte in fallimento.
    private func attemptDelivery(
        event: EventBusEvent,
        to subscription: EventSubscription,
        attemptNumber: Int
    ) async -> Bool {
        do {
            try await subscription.handler(event)

            let attempt = DeliveryAttempt(
                eventId: event.eventId,
                subscriptionId: subscription.id,
                attemptNumber: attemptNumber,
                success: true
            )
            appendAttempt(attempt)
            return true

        } catch {
            let attempt = DeliveryAttempt(
                eventId: event.eventId,
                subscriptionId: subscription.id,
                attemptNumber: attemptNumber,
                success: false,
                error: error.localizedDescription
            )
            appendAttempt(attempt)
            return false
        }
    }

    /// Wrappa attemptDelivery con un timeout per evitare handler bloccati.
    private func deliverWithTimeout(
        event: EventBusEvent,
        to subscription: EventSubscription,
        attemptNumber: Int
    ) async -> Bool {
        let timeoutNs = deliveryTimeoutMs * 1_000_000
        do {
            return try await withThrowingTaskGroup(of: Bool.self) { group in
                group.addTask {
                    await self.attemptDelivery(
                        event: event,
                        to: subscription,
                        attemptNumber: attemptNumber
                    )
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: timeoutNs)
                    return false
                }
                // Il primo a completare vince; l'altro viene cancellato.
                let result = try await group.next() ?? false
                group.cancelAll()
                return result
            }
        } catch {
            return false
        }
    }

    private func processDelivery(recordKey: String) async {
        defer { deliveryTasks.removeValue(forKey: recordKey) }
        guard var record = pendingRecords[recordKey] else { return }

        for attemptNumber in 1...maxAttempts {
            if Task.isCancelled {
                pendingRecords.removeValue(forKey: recordKey)
                return
            }

            record.attempts = attemptNumber
            record.lastAttemptAt = Date()
            pendingRecords[recordKey] = record

            let success = await deliverWithTimeout(
                event: record.event,
                to: record.subscription,
                attemptNumber: attemptNumber
            )

            if success {
                var delivered = record.event
                delivered.deliveryStatus = .delivered
                delivered.deliveryAttempts = attemptNumber
                totalDelivered += 1
                pendingRecords.removeValue(forKey: recordKey)
                return
            }

            record.lastError = "delivery_failed_attempt_\(attemptNumber)"
            pendingRecords[recordKey] = record

            if attemptNumber < maxAttempts {
                let delay = calculateBackoff(attempt: attemptNumber)
                try? await Task.sleep(nanoseconds: delay * 1_000_000)
            }
        }

        var deadEvent = record.event
        deadEvent.deliveryStatus = .deadLettered
        deadEvent.deliveryAttempts = maxAttempts
        totalFailed += 1
        pendingRecords.removeValue(forKey: recordKey)
        await deadLetterQueue.enqueue(
            deadEvent,
            reason: .maxAttemptsExceeded(maxAttempts)
        )
    }

    private func appendAttempt(_ attempt: DeliveryAttempt) {
        attemptLog.append(attempt)
        let overflow = attemptLog.count - maxAttemptLogEntries
        if overflow > 0 {
            attemptLog.removeFirst(overflow)
        }
    }

    // MARK: - Backoff

    /// Exponential backoff con jitter deterministico (§5.11).
    /// `delay = min(base * 2^attempt + jitter, maxDelay)`
    func calculateBackoff(attempt: Int) -> UInt64 {
        let exponential = baseDelayMs * (1 << UInt64(attempt - 1))
        let jitter = UInt64((attempt * 37) % Int(min(exponential + 1, 500)))
        return min(exponential + jitter, maxDelayMs)
    }

    // MARK: - Query

    public func pendingCount() -> Int {
        pendingRecords.count
    }

    public func recentAttempts(limit: Int = 50) -> [DeliveryAttempt] {
        Array(attemptLog.suffix(limit))
    }

    /// Percentuale di successo nelle consegne.
    public func successRate() -> Double {
        let total = totalDelivered + totalFailed
        guard total > 0 else { return 1.0 }
        return Double(totalDelivered) / Double(total)
    }

    public func cancelAll() {
        for task in deliveryTasks.values {
            task.cancel()
        }
        deliveryTasks.removeAll()
        pendingRecords.removeAll()
    }

    // MARK: - Reset

    public func reset() {
        cancelAll()
        pendingRecords.removeAll()
        attemptLog.removeAll()
        totalDelivered = 0
        totalFailed = 0
    }
}
