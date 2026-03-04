import CoderEngine
import Foundation

actor LanguageService {
    private let configuration: LanguageServiceConfiguration
    private let localAdapter: LanguageServiceAdapter
    private let sourceKitAdapter: LanguageServiceAdapter?

    init(
        codebaseIndex: CodebaseIndex,
        configuration: LanguageServiceConfiguration = .load(),
        sourceKitAdapterOverride: LanguageServiceAdapter? = nil
    ) {
        self.configuration = configuration
        self.localAdapter = LocalIndexLanguageAdapter(index: codebaseIndex)
        if let sourceKitAdapterOverride {
            self.sourceKitAdapter = sourceKitAdapterOverride
        } else if configuration.sourceKitLSPEnabled {
            self.sourceKitAdapter = SourceKitLSPAdapter(executablePath: configuration.sourceKitLSPPath)
        } else {
            self.sourceKitAdapter = nil
        }
    }

    func goToDefinition(symbol: String, fileHint: String? = nil) async throws -> [LanguageLocation] {
        let normalized = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }
        try ensureEnabled()
        return try await executeWithFallback(
            operation: { try await $0.goToDefinition(symbol: normalized, fileHint: fileHint) },
            shouldFallback: { $0.isEmpty }
        )
    }

    func hover(symbol: String, fileHint: String? = nil) async throws -> LanguageHoverResult? {
        let normalized = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        try ensureEnabled()
        return try await executeWithFallback(
            operation: { try await $0.hover(symbol: normalized, fileHint: fileHint) },
            shouldFallback: { result in
                guard let result else { return true }
                return result.contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        )
    }

    func findReferences(symbol: String, limit: Int = 200) async throws -> [LanguageLocation] {
        let normalized = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }
        try ensureEnabled()
        return try await executeWithFallback(
            operation: { try await $0.findReferences(symbol: normalized, limit: max(1, limit)) },
            shouldFallback: { $0.isEmpty }
        )
    }

    func rename(oldName: String, newName: String) async throws -> LanguageRenamePlan {
        let oldNormalized = oldName.trimmingCharacters(in: .whitespacesAndNewlines)
        let newNormalized = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !oldNormalized.isEmpty, !newNormalized.isEmpty else {
            return LanguageRenamePlan(oldName: oldName, newName: newName, references: [], source: .localIndex)
        }
        try ensureEnabled()
        return try await executeWithFallback(
            operation: { try await $0.rename(oldName: oldNormalized, newName: newNormalized) },
            shouldFallback: { $0.references.isEmpty }
        )
    }

    private func ensureEnabled() throws {
        if !configuration.languageServiceEnabled {
            throw LanguageServiceError.disabled
        }
    }

    private func executeWithFallback<T>(
        operation: @escaping (LanguageServiceAdapter) async throws -> T,
        shouldFallback: @escaping @Sendable (T) -> Bool
    ) async throws -> T {
        if let sourceKitAdapter {
            do {
                let sourceKitResult = try await operation(sourceKitAdapter)
                if shouldFallback(sourceKitResult) {
                    // Keep behavior consistent across definition/hover/references/rename.
                    return try await operation(localAdapter)
                }
                return sourceKitResult
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                return try await operation(localAdapter)
            }
        }
        return try await operation(localAdapter)
    }
}
