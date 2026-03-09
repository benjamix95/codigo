import Foundation

public actor EntityExecutionCoordinator {
    private var activeEntities: Set<String> = []

    public init() {}

    public func withExclusiveAccess<T: Sendable>(
        entityId: String,
        operation: @Sendable () async throws -> T
    ) async rethrows -> T {
        while activeEntities.contains(entityId) {
            await Task.yield()
        }
        activeEntities.insert(entityId)
        defer { activeEntities.remove(entityId) }
        return try await operation()
    }
}
