import Foundation

// MARK: - Linting Service

/// Servizio di linting codice con supporto multi-linter.
/// Actor-based per thread safety, feature flag per abilitazione/disabilitazione.
actor LintingService {
    let configuration: LintingServiceConfiguration
    private let swiftLintAdapter: SwiftLintAdapter

    init(configuration: LintingServiceConfiguration = .load()) {
        self.configuration = configuration
        self.swiftLintAdapter = SwiftLintAdapter(
            executablePath: configuration.swiftLintPath
        )
    }

    // MARK: - Public API

    /// Lint di un singolo file.
    func lint(filePath: String) async -> LintResult {
        guard configuration.isEnabled else {
            return .failure(
                filePath: filePath,
                error: configuration.disabledReason ?? "Linting disabilitato."
            )
        }

        let adapter = resolveAdapter(for: filePath)
        return await adapter.lint(filePath: filePath)
    }

    /// Lint di una directory (tutti i file supportati).
    func lintDirectory(at path: String) async -> [LintResult] {
        guard configuration.isEnabled else {
            return [.failure(
                filePath: path,
                error: configuration.disabledReason ?? "Linting disabilitato."
            )]
        }

        let adapter = resolveAdapter(for: path)
        return await adapter.lintDirectory(at: path)
    }

    /// Lint on-save: esegue lint e opzionalmente auto-fix.
    func lintOnSave(filePath: String) async -> LintResult {
        guard configuration.lintOnSave else {
            return .failure(filePath: filePath, error: "Lint-on-save disabilitato.")
        }

        if configuration.autoFixEnabled {
            return await autoFix(filePath: filePath)
        }
        return await lint(filePath: filePath)
    }

    /// Auto-fix dei problemi risolvibili automaticamente.
    func autoFix(filePath: String) async -> LintResult {
        guard configuration.isEnabled else {
            return .failure(filePath: filePath, error: "Linting disabilitato.")
        }

        guard let swiftAdapter = resolveAdapter(for: filePath) as? SwiftLintAdapter else {
            return .failure(filePath: filePath, error: "Auto-fix non supportato per questo tipo di file.")
        }

        return await swiftAdapter.autoFix(filePath: filePath)
    }

    /// Verifica se il linter è disponibile.
    func isLinterAvailable() async -> Bool {
        await swiftLintAdapter.isAvailable()
    }

    /// Restituisce la configurazione corrente.
    func currentConfiguration() -> LintingServiceConfiguration {
        configuration
    }

    // MARK: - Private

    private func resolveAdapter(for filePath: String) -> LintingAdapter {
        let ext = (filePath as NSString).pathExtension.lowercased()
        switch ext {
        case "swift":
            return swiftLintAdapter
        default:
            return swiftLintAdapter
        }
    }
}
