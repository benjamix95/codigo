import Foundation

extension EventBus {
    // MARK: - Lifecycle

    public func shutdown() async {
        isShutdown = true
        subscriptions.removeAll()
        subscriptionIdsByType.removeAll()
        wildcardSubscriptionIds.removeAll()
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

    // MARK: - Delivery

    func deliverConcurrently(
        _ event: EventBusEvent,
        to subscriptions: [EventSubscription]
    ) async {
        await withTaskGroup(of: Void.self) { group in
            for subscription in subscriptions {
                group.addTask {
                    await self.deliveryManager.deliver(
                        event: event,
                        to: subscription
                    )
                }
            }
        }
    }

    // MARK: - Idempotency Cache

    func pruneIdempotencyKeysIfNeeded(now: Date) {
        guard shouldPruneIdempotencyKeys(now: now) else { return }
        pruneIdempotencyKeysInternal(olderThan: idempotencyKeyMaxAge, now: now)
    }

    private func shouldPruneIdempotencyKeys(now: Date) -> Bool {
        if idempotencyKeyMaxAge <= 0 {
            return true
        }

        if seenIdempotencyKeys.count >= maxTrackedIdempotencyKeys {
            return true
        }

        let pruneThreshold = max(256, maxTrackedIdempotencyKeys / 2)
        guard seenIdempotencyKeys.count >= pruneThreshold else {
            return false
        }

        return now.timeIntervalSince(lastPruneTime) >= pruneThrottleInterval
    }

    func registerIdempotencyKey(_ key: String, at now: Date) {
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
            lastPruneTime = now
            return
        }

        lastPruneTime = now

        let cutoff = now.addingTimeInterval(-maxAge)
        var removedCount = 0
        for key in idempotencyKeyOrder {
            guard let timestamp = seenIdempotencyKeys[key],
                  timestamp < cutoff else { break }
            seenIdempotencyKeys.removeValue(forKey: key)
            removedCount += 1
        }
        if removedCount > 0 {
            idempotencyKeyOrder.removeFirst(removedCount)
        }

    }
}
