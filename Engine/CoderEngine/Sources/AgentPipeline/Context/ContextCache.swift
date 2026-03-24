import Foundation

// MARK: - ContextCacheConfig

/// Configurazione della cache di contesto (§8.3).
public struct ContextCacheConfig: Sendable, Equatable {
    public var maxEntries: Int
    public var ttlMs: Int
    public var poisoningSuspectAgeMs: Int

    public init(
        maxEntries: Int = 50,
        ttlMs: Int = 300_000,
        poisoningSuspectAgeMs: Int = 120_000
    ) {
        self.maxEntries = maxEntries
        self.ttlMs = ttlMs
        self.poisoningSuspectAgeMs = poisoningSuspectAgeMs
    }
}

// MARK: - CacheEvictionReason

/// Motivo di eviction dalla cache (§8.3).
public enum CacheEvictionReason: String, Sendable, Equatable {
    case lru
    case ttlExpired = "ttl_expired"
    case invalidated
    case poisoningSuspect = "poisoning_suspect"
}

// MARK: - ContextCacheEntry

/// Entry interna della cache con metadati LRU.
struct ContextCacheEntry: Sendable {
    let key: String
    let bundle: ContextBundle
    let insertedAt: Date
    var accessedAt: Date
    var hitCount: Int
}

// MARK: - ContextBundle

/// Bundle di contesto immutabile dopo l'inserimento (§8.3).
public struct ContextBundle: Sendable, Equatable {
    public let items: [RankedContextItem]
    public let totalTokens: Int
    public let compressionApplied: Bool

    public init(
        items: [RankedContextItem],
        totalTokens: Int,
        compressionApplied: Bool = false
    ) {
        self.items = items
        self.totalTokens = totalTokens
        self.compressionApplied = compressionApplied
    }
}

// MARK: - ContextCacheDelegate

/// Delegato per ricevere notifiche di eviction (metriche).
public protocol ContextCacheDelegate: Sendable {
    func cacheDidEvict(key: String, reason: CacheEvictionReason) async
}

// MARK: - ContextCache

/// Cache LRU di contesto con TTL per evitare rebuild (§8.3).
///
/// Chiave: `task_signature = hash(file_scope + symbol_scope + task_type + commit_sha)`
///
/// Regole:
/// - Cache hit → riutilizza il bundle, skip search/ranking
/// - Cache miss → build completo, salva in cache
/// - Invalidazione: file_scope cambiato, symbol_scope modificato, task_type cambiato
/// - TTL max: 300s (5 min)
/// - Max entries: 50
/// - Eviction: LRU
public actor ContextCache {

    private var entries: [String: ContextCacheEntry] = [:]
    private let config: ContextCacheConfig
    public var delegate: (any ContextCacheDelegate)?

    private var totalHits: Int = 0
    private var totalMisses: Int = 0
    private var totalEvictions: Int = 0

    public init(
        config: ContextCacheConfig = ContextCacheConfig(),
        delegate: (any ContextCacheDelegate)? = nil
    ) {
        self.config = config
        self.delegate = delegate
    }

    // MARK: - Lookup

    /// Cerca un bundle in cache. Aggiorna `accessedAt` su hit.
    public func get(_ key: String) -> ContextBundle? {
        guard var entry = entries[key] else {
            totalMisses += 1
            return nil
        }
        let now = Date()
        let ageMs = now.timeIntervalSince(entry.insertedAt) * 1000
        if ageMs > Double(config.ttlMs) {
            entries.removeValue(forKey: key)
            totalEvictions += 1
            totalMisses += 1
            Task { [delegate] in
                await delegate?.cacheDidEvict(
                    key: key, reason: .ttlExpired
                )
            }
            return nil
        }
        entry.accessedAt = now
        entry.hitCount += 1
        entries[key] = entry
        totalHits += 1
        return entry.bundle
    }

    // MARK: - Insert

    /// Inserisce un bundle in cache. Evict LRU se necessario.
    public func put(_ key: String, bundle: ContextBundle) async {
        if entries.count >= config.maxEntries, entries[key] == nil {
            await evictLRU()
        }
        let now = Date()
        entries[key] = ContextCacheEntry(
            key: key,
            bundle: bundle,
            insertedAt: now,
            accessedAt: now,
            hitCount: 0
        )
    }

    // MARK: - Invalidate

    /// Invalida manualmente un'entry (file_scope/symbol_scope cambiati).
    public func invalidate(_ key: String) async {
        guard entries.removeValue(forKey: key) != nil else { return }
        totalEvictions += 1
        await delegate?.cacheDidEvict(key: key, reason: .invalidated)
    }

    /// Invalida un'entry per sospetto poisoning (confidence < 0.3).
    public func invalidateAsPoisoning(_ key: String) async {
        guard entries.removeValue(forKey: key) != nil else { return }
        totalEvictions += 1
        await delegate?.cacheDidEvict(
            key: key, reason: .poisoningSuspect
        )
    }

    // MARK: - Periodic Cleanup

    /// Pulizia periodica: rimuove TTL expired + entry mai usate
    /// dopo `poisoningSuspectAgeMs` (§8.3).
    public func periodicCleanup() async {
        guard !entries.isEmpty else { return }
        let now = Date()
        var toEvict: [(String, CacheEvictionReason)] = []

        for (key, entry) in entries {
            let ageMs = now.timeIntervalSince(entry.insertedAt) * 1000
            if ageMs > Double(config.ttlMs) {
                toEvict.append((key, .ttlExpired))
            } else if entry.hitCount == 0 {
                let idleMs = now.timeIntervalSince(entry.accessedAt) * 1000
                if idleMs > Double(config.poisoningSuspectAgeMs) {
                    toEvict.append((key, .poisoningSuspect))
                }
            }
        }

        for (key, reason) in toEvict {
            entries.removeValue(forKey: key)
            totalEvictions += 1
            await delegate?.cacheDidEvict(key: key, reason: reason)
        }
    }

    // MARK: - Metrics

    public func hitRate() -> Double {
        let total = totalHits + totalMisses
        guard total > 0 else { return 0 }
        return Double(totalHits) / Double(total)
    }

    public func size() -> Int {
        entries.count
    }

    public func evictionCount() -> Int {
        totalEvictions
    }

    // MARK: - Helpers

    /// Genera la task_signature deterministica (§8.3).
    public static func taskSignature(
        fileScope: [String],
        symbolScope: [String],
        taskType: TaskType,
        commitSha: String
    ) -> String {
        let combined = fileScope.sorted().joined(separator: "|")
            + ":" + symbolScope.sorted().joined(separator: "|")
            + ":" + taskType.rawValue
            + ":" + commitSha
        var hash: UInt64 = 5381
        for byte in combined.utf8 {
            hash = hash &* 33 &+ UInt64(byte)
        }
        return String(hash, radix: 16)
    }

    // MARK: - Private

    private func evictLRU() async {
        guard let lruKey = entries
            .min(by: { $0.value.accessedAt < $1.value.accessedAt })?
            .key
        else { return }
        entries.removeValue(forKey: lruKey)
        totalEvictions += 1
        await delegate?.cacheDidEvict(key: lruKey, reason: .lru)
    }

    public func reset() {
        entries.removeAll()
        totalHits = 0
        totalMisses = 0
        totalEvictions = 0
    }
}
