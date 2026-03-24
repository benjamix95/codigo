import Foundation

// MARK: - EventSubscription

/// Sottoscrizione registrata presso l'EventBus.
public struct EventSubscription: Sendable {
    public let id: String
    public let filter: EventSubscriptionFilter
    public let handler: @Sendable (EventBusEvent) async throws -> Void

    public init(
        id: String,
        filter: EventSubscriptionFilter,
        handler: @escaping @Sendable (EventBusEvent) async throws -> Void
    ) {
        self.id = id
        self.filter = filter
        self.handler = handler
    }
}

// MARK: - EventSubscriptionFilter

/// Filtro per selezionare quali eventi ricevere.
public struct EventSubscriptionFilter: Sendable, Equatable {
    public var eventTypes: Set<PipelineEventType>?
    public var jobId: String?
    public var taskId: String?

    public init(
        eventTypes: Set<PipelineEventType>? = nil,
        jobId: String? = nil,
        taskId: String? = nil
    ) {
        self.eventTypes = eventTypes
        self.jobId = jobId
        self.taskId = taskId
    }

    /// Restituisce `true` se l'evento corrisponde a questo filtro.
    public func matches(_ event: EventBusEvent) -> Bool {
        if let types = eventTypes, !types.contains(event.type) {
            return false
        }
        if let jid = jobId, event.jobId != jid {
            return false
        }
        if let tid = taskId, event.taskId != tid {
            return false
        }
        return true
    }
}

// MARK: - EventBusProtocol

/// Interfaccia pubblica dell'EventBus (§6.9).
public protocol EventBusProtocol: Sendable {
    func publish(_ event: EventBusEvent) async throws
    func subscribe(_ subscription: EventSubscription) async
    func unsubscribe(id: String) async
    func pendingCount() async -> Int
    func shutdown() async
}

// MARK: - EventBusError

public enum EventBusError: Error, Sendable, Equatable {
    case busShutdown
    case invalidEvent(reason: String)
    case duplicateIdempotencyKey(String)
}

// MARK: - EventBus

/// Event Bus interno della pipeline con at-least-once delivery (§6.9).
///
/// Responsabilità:
/// - Ricezione e validazione eventi
/// - Routing verso subscriber tramite filtro
/// - Deduplicazione tramite idempotency key
/// - Delega delivery a `EventDeliveryManager`
/// - Inoltro a `DeadLetterQueue` per eventi non consegnabili
public actor EventBus: EventBusProtocol {

    private var subscriptions: [String: EventSubscription] = [:]
    private var seenIdempotencyKeys: [String: Date] = [:]
    private var idempotencyKeyOrder: [String] = []
    private var sequenceCounter: UInt64 = 0
    private var isShutdown = false

    private let deliveryManager: EventDeliveryManager
    private let deadLetterQueue: DeadLetterQueue
    private let maxTrackedIdempotencyKeys: Int
    private let idempotencyKeyMaxAge: TimeInterval

    public init(
        deliveryManager: EventDeliveryManager,
        deadLetterQueue: DeadLetterQueue,
        maxTrackedIdempotencyKeys: Int = 10_000,
        idempotencyKeyMaxAge: TimeInterval = 3_600
    ) {
        self.deliveryManager = deliveryManager
        self.deadLetterQueue = deadLetterQueue
        self.maxTrackedIdempotencyKeys = max(1, maxTrackedIdempotencyKeys)
        self.idempotencyKeyMaxAge = max(0, idempotencyKeyMaxAge)
    }

    /// Convenience init con configurazione di default.
    public init(
        maxDeliveryAttempts: Int = 3,
        dlqCapacity: Int = 1000,
        maxTrackedIdempotencyKeys: Int = 10_000,
        idempotencyKeyMaxAge: TimeInterval = 3_600
    ) {
        let dlq = DeadLetterQueue(capacity: dlqCapacity)
        self.deadLetterQueue = dlq
        self.deliveryManager = EventDeliveryManager(
            maxAttempts: maxDeliveryAttempts,
            deadLetterQueue: dlq
        )
        self.maxTrackedIdempotencyKeys = max(1, maxTrackedIdempotencyKeys)
        self.idempotencyKeyMaxAge = max(0, idempotencyKeyMaxAge)
    }

    // MARK: - Publish

    public func publish(_ event: EventBusEvent) async throws {
        guard !isShutdown else {
            throw EventBusError.busShutdown
        }

        try event.validate()
        let now = Date()
        pruneIdempotencyKeysInternal(olderThan: idempotencyKeyMaxAge, now: now)

        if seenIdempotencyKeys[event.idempotencyKey] != nil {
            throw EventBusError.duplicateIdempotencyKey(event.idempotencyKey)
        }

        registerIdempotencyKey(event.idempotencyKey, at: now)
        sequenceCounter += 1

        var enriched = event
        enriched.sequenceNumber = sequenceCounter
        enriched.deliveryStatus = .pending

        let matchingSubscriptions = subscriptions.values.filter { sub in
            sub.filter.matches(enriched)
        }

        if matchingSubscriptions.isEmpty {
            var unroutable = enriched
            unroutable.deliveryStatus = .deadLettered
            await deadLetterQueue.enqueue(
                unroutable,
                reason: .noSubscribers
            )
            return
        }

        for subscription in matchingSubscriptions {
            await deliveryManager.deliver(
                event: enriched,
                to: subscription
            )
        }
    }

    // MARK: - Subscribe / Unsubscribe

    public func subscribe(_ subscription: EventSubscription) async {
        subscriptions[subscription.id] = subscription
    }

    public func unsubscribe(id: String) async {
        subscriptions.removeValue(forKey: id)
    }

    // MARK: - Query

    public func pendingCount() async -> Int {
        await deliveryManager.pendingCount()
    }

    public func deadLetterCount() async -> Int {
        await deadLetterQueue.count()
    }

    public func subscriberCount() -> Int {
        subscriptions.count
    }

    // MARK: - Lifecycle

    public func shutdown() async {
        isShutdown = true
        subscriptions.removeAll()
        seenIdempotencyKeys.removeAll()
        idempotencyKeyOrder.removeAll()
        await deliveryManager.cancelAll()
    }

    /// Ripulisce le idempotency key più vecchie di `maxAge`.
    /// Previene crescita illimitata del set in-memory.
    public func pruneIdempotencyKeys(olderThan maxAge: TimeInterval) {
        pruneIdempotencyKeysInternal(olderThan: maxAge, now: Date())
    }

    /// Reset completo — utile per i test.
    public func reset() async {
        subscriptions.removeAll()
        seenIdempotencyKeys.removeAll()
        idempotencyKeyOrder.removeAll()
        sequenceCounter = 0
        isShutdown = false
        await deliveryManager.reset()
    }

    // MARK: - Idempotency Cache

    private func registerIdempotencyKey(_ key: String, at now: Date) {
        seenIdempotencyKeys[key] = now
        idempotencyKeyOrder.append(key)

        while seenIdempotencyKeys.count > maxTrackedIdempotencyKeys {
            evictOldestTrackedIdempotencyKey()
        }
    }

    private func evictOldestTrackedIdempotencyKey() {
        while !idempotencyKeyOrder.isEmpty {
            let oldestKey = idempotencyKeyOrder.removeFirst()
            if seenIdempotencyKeys.removeValue(forKey: oldestKey) != nil {
                break
            }
        }
    }

    private func pruneIdempotencyKeysInternal(olderThan maxAge: TimeInterval, now: Date) {
        if maxAge <= 0 {
            seenIdempotencyKeys.removeAll()
            idempotencyKeyOrder.removeAll()
            return
        }

        let cutoff = now.addingTimeInterval(-maxAge)
        seenIdempotencyKeys = seenIdempotencyKeys.filter { _, timestamp in
            timestamp >= cutoff
        }
        idempotencyKeyOrder.removeAll { key in
            seenIdempotencyKeys[key] == nil
        }

        // Hard cap: se dopo age-pruning siamo ancora sopra il limite,
        // evinciamo i più vecchi fino all'80% della capacità.
        let hardCapTarget = maxTrackedIdempotencyKeys * 4 / 5
        while seenIdempotencyKeys.count > hardCapTarget {
            guard !idempotencyKeyOrder.isEmpty else { break }
            evictOldestTrackedIdempotencyKey()
        }
    }
}
