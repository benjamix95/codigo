import Foundation

public struct SearchBackendMetrics: Codable, Equatable, Sendable {
    public let backendKind: SearchEngineBackendKind
    public let elapsedMs: Int
    public let hitCount: Int
    public let usedFallback: Bool
    public let loadedRustLibrary: Bool
    public let errorMessage: String?

    public init(
        backendKind: SearchEngineBackendKind,
        elapsedMs: Int,
        hitCount: Int,
        usedFallback: Bool,
        loadedRustLibrary: Bool,
        errorMessage: String?
    ) {
        self.backendKind = backendKind
        self.elapsedMs = elapsedMs
        self.hitCount = hitCount
        self.usedFallback = usedFallback
        self.loadedRustLibrary = loadedRustLibrary
        self.errorMessage = errorMessage
    }
}
