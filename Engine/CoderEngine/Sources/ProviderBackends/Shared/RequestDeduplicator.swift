import Foundation

/// Deduplicatore generico per richieste API concorrenti identiche.
///
/// Se una richiesta con la stessa chiave è già in-flight, i chiamanti successivi
/// attendono il risultato della prima — evitando duplicati simultanei.
///
/// Uso:
/// ```
/// let dedup = RequestDeduplicator<String, [Model]>()
/// let models = try await dedup.deduplicated(key: "openai-models") {
///     try await fetchModels()
/// }
/// ```
public actor RequestDeduplicator<Key: Hashable & Sendable, Value: Sendable> {

    private var inFlight: [Key: Task<Value, Error>] = [:]

    public init() {}

    /// Esegue `work` solo se nessuna richiesta con la stessa `key` è in-flight.
    /// Altrimenti attende il risultato della richiesta già in corso.
    public func deduplicated(
        key: Key,
        work: @Sendable @escaping () async throws -> Value
    ) async throws -> Value {
        if let existing = inFlight[key] {
            return try await existing.value
        }

        let task = Task<Value, Error> {
            try await work()
        }
        inFlight[key] = task

        do {
            let result = try await task.value
            inFlight.removeValue(forKey: key)
            return result
        } catch {
            inFlight.removeValue(forKey: key)
            throw error
        }
    }

    /// Invalida una richiesta in-flight (utile per force-refresh).
    public func invalidate(key: Key) {
        inFlight[key]?.cancel()
        inFlight.removeValue(forKey: key)
    }

    /// Numero di richieste in-flight.
    public var inFlightCount: Int {
        inFlight.count
    }
}
