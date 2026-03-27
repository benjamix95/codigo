import Foundation
import os

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

    var subscriptions: [String: EventSubscription] = [:]
    /// Reverse index: eventType → subscription IDs that listen for that type.
    var subscriptionIdsByType: [PipelineEventType: Set<String>] = [:]
    /// Subscription IDs with no eventType filter (wildcard — match all events).
    var wildcardSubscriptionIds: Set<String> = []
    var seenIdempotencyKeys: [String: Date] = [:]
    var idempotencyKeyOrder: [String] = []
    var sequenceCounter: UInt64 = 0
    var isShutdown = false

    let deliveryManager: EventDeliveryManager
    private let deadLetterQueue: DeadLetterQueue
    let maxTrackedIdempotencyKeys: Int
    let idempotencyKeyMaxAge: TimeInterval
    var lastPruneTime: Date = .distantPast
    let pruneThrottleInterval: TimeInterval = 5.0

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
        #if DEBUG
        let publishSignpostID = OSSignpostID(log: EventBusPublishSignpost.log)
        os_signpost(
            .begin,
            log: EventBusPublishSignpost.log,
            name: "EventBusPublish",
            signpostID: publishSignpostID,
            "%{public}s",
            event.type.rawValue
        )
        defer {
            os_signpost(
                .end,
                log: EventBusPublishSignpost.log,
                name: "EventBusPublish",
                signpostID: publishSignpostID
            )
        }
        #endif

        guard !isShutdown else {
            throw EventBusError.busShutdown
        }

        try event.validate()
        let now = Date()
        pruneIdempotencyKeysIfNeeded(now: now)

        if seenIdempotencyKeys[event.idempotencyKey] != nil {
            throw EventBusError.duplicateIdempotencyKey(event.idempotencyKey)
        }

        registerIdempotencyKey(event.idempotencyKey, at: now)
        sequenceCounter += 1

        var enriched = event
        enriched.sequenceNumber = sequenceCounter
        enriched.deliveryStatus = .pending

        let matchingSubscriptions = candidateSubscriptions(for: enriched)

        if matchingSubscriptions.isEmpty {
            var unroutable = enriched
            unroutable.deliveryStatus = .deadLettered
            await deadLetterQueue.enqueue(
                unroutable,
                reason: .noSubscribers
            )
            return
        }

        await deliverConcurrently(enriched, to: matchingSubscriptions)
    }

    // MARK: - Subscribe / Unsubscribe

    public func subscribe(_ subscription: EventSubscription) async {
        if let old = subscriptions[subscription.id] {
            removeFromIndex(id: old.id, filter: old.filter)
        }
        subscriptions[subscription.id] = subscription
        addToIndex(id: subscription.id, filter: subscription.filter)
    }

    public func unsubscribe(id: String) async {
        if let sub = subscriptions.removeValue(forKey: id) {
            removeFromIndex(id: sub.id, filter: sub.filter)
        }
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

    // MARK: - Index Management

    private func addToIndex(id: String, filter: EventSubscriptionFilter) {
        if let types = filter.eventTypes {
            for type in types {
                subscriptionIdsByType[type, default: []].insert(id)
            }
        } else {
            wildcardSubscriptionIds.insert(id)
        }
    }

    private func removeFromIndex(id: String, filter: EventSubscriptionFilter) {
        if let types = filter.eventTypes {
            for type in types {
                subscriptionIdsByType[type]?.remove(id)
                if subscriptionIdsByType[type]?.isEmpty == true {
                    subscriptionIdsByType.removeValue(forKey: type)
                }
            }
        } else {
            wildcardSubscriptionIds.remove(id)
        }
    }

    private func candidateSubscriptions(for event: EventBusEvent) -> [EventSubscription] {
        var candidateIds = wildcardSubscriptionIds
        if let indexed = subscriptionIdsByType[event.type] {
            candidateIds.formUnion(indexed)
        }
        return candidateIds.compactMap { id in
            guard let sub = subscriptions[id] else { return nil }
            if let jid = sub.filter.jobId, event.jobId != jid { return nil }
            if let tid = sub.filter.taskId, event.taskId != tid { return nil }
            return sub
        }
    }
}
