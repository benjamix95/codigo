import CoderEngine
import Foundation

actor LanguageService {
    let configuration: LanguageServiceConfiguration
    private let localAdapter: LanguageServiceAdapter
    private let sourceKitAdapter: LanguageServiceAdapter?

    init(
        codebaseIndex: CodebaseIndex,
        configuration: LanguageServiceConfiguration = .load(),
        sourceKitAdapterOverride: LanguageServiceAdapter? = nil
    ) {
        self.configuration = configuration
        self.localAdapter = LocalIndexLanguageAdapter(index: codebaseIndex)
        self.sourceKitAdapter = configuration.sourceKitLSPEnabled
            ? (sourceKitAdapterOverride ?? SourceKitLSPAdapter(executablePath: configuration.sourceKitLSPPath))
            : nil
    }

    func goToDefinition(symbol: String, fileHint: String? = nil) async throws -> [LanguageLocation] {
        let normalized = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }
        try ensureEnabled()
        let locations = try await executeWithFallback(
            operation: { try await $0.goToDefinition(symbol: normalized, fileHint: fileHint) },
            shouldFallback: { $0.isEmpty }
        )
        return LanguageServiceResultCanonicalizer.canonicalize(
            locations: locations,
            symbolName: normalized
        )
    }

    func hover(symbol: String, fileHint: String? = nil) async throws -> LanguageHoverResult? {
        let normalized = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        try ensureEnabled()
        let hover = try await executeWithFallback(
            operation: { try await $0.hover(symbol: normalized, fileHint: fileHint) },
            shouldFallback: { result in
                guard let result else { return true }
                return result.contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        )
        return LanguageServiceResultCanonicalizer.canonicalize(hover: hover)
    }

    func findReferences(symbol: String, limit: Int = 200) async throws -> [LanguageLocation] {
        let normalized = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return [] }
        let cappedLimit = max(1, limit)
        try ensureEnabled()
        let references = try await executeWithFallback(
            operation: { try await $0.findReferences(symbol: normalized, limit: cappedLimit) },
            shouldFallback: { $0.isEmpty }
        )
        return LanguageServiceResultCanonicalizer.canonicalize(
            locations: references,
            symbolName: normalized,
            limit: cappedLimit
        )
    }

    func rename(oldName: String, newName: String) async throws -> LanguageRenamePlan {
        let oldNormalized = oldName.trimmingCharacters(in: .whitespacesAndNewlines)
        let newNormalized = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !oldNormalized.isEmpty, !newNormalized.isEmpty else {
            return LanguageRenamePlan(
                oldName: oldNormalized,
                newName: newNormalized,
                references: [],
                source: .localIndex
            )
        }
        try ensureEnabled()
        let renamePlan = try await executeWithFallback(
            operation: { try await $0.rename(oldName: oldNormalized, newName: newNormalized) },
            shouldFallback: { $0.references.isEmpty }
        )
        return LanguageServiceResultCanonicalizer.canonicalize(
            renamePlan: renamePlan,
            requestedOldName: oldNormalized,
            requestedNewName: newNormalized
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
