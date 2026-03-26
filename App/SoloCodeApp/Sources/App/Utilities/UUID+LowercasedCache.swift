import Foundation

extension UUID {
    /// Cached lowercased UUID string. Avoids repeated `uuidString.lowercased()`
    /// allocations. Thread-safe via NSCache.
    var lowercasedString: String {
        UUIDLowercasedCache.shared.string(for: self)
    }
}

/// Global cache for lowercased UUID strings.
/// NSCache is thread-safe and automatically evicts under memory pressure.
private final class UUIDLowercasedCache: @unchecked Sendable {
    static let shared = UUIDLowercasedCache()

    private let cache = NSCache<NSUUID, NSString>()

    init() {
        cache.countLimit = 2048
    }

    func string(for uuid: UUID) -> String {
        let key = uuid as NSUUID
        if let cached = cache.object(forKey: key) {
            return cached as String
        }
        let value = uuid.uuidString.lowercased() as NSString
        cache.setObject(value, forKey: key)
        return value as String
    }
}
