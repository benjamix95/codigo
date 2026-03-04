import Foundation

// MARK: - Formatting Service

/// Servizio di formattazione codice con supporto multi-formatter.
/// Actor-based per thread safety, feature flag per abilitazione/disabilitazione.
actor FormattingService {
    let configuration: FormattingServiceConfiguration
    private let swiftFormatAdapter: SwiftFormatAdapter
    private let formattingOptions: FormattingOptions

    init(
        configuration: FormattingServiceConfiguration = .load(),
        options: FormattingOptions = .default
    ) {
        self.configuration = configuration
        self.formattingOptions = options
        self.swiftFormatAdapter = SwiftFormatAdapter(
            executablePath: configuration.swiftFormatPath
        )
    }

    // MARK: - Public API

    /// Formatta il contenuto di un file.
    func format(content: String, filePath: String) async -> FormattingResult {
        guard configuration.isEnabled else {
            return .failure(
                filePath: filePath,
                error: configuration.disabledReason ?? "Formattazione disabilitata."
            )
        }

        let adapter = resolveAdapter(for: filePath)
        return await adapter.format(
            content: content,
            filePath: filePath,
            options: formattingOptions
        )
    }

    /// Formatta un file direttamente dal disco.
    func formatFile(at path: String) async -> FormattingResult {
        guard configuration.isEnabled else {
            return .failure(
                filePath: path,
                error: configuration.disabledReason ?? "Formattazione disabilitata."
            )
        }

        let adapter = resolveAdapter(for: path)
        return await adapter.formatFile(at: path, options: formattingOptions)
    }

    /// Formatta e salva il file (per format-on-save).
    func formatAndSave(at path: String) async -> FormattingResult {
        guard configuration.formatOnSave else {
            return .failure(filePath: path, error: "Format-on-save disabilitato.")
        }

        let result = await formatFile(at: path)
        guard result.isSuccess, result.didChange else { return result }

        do {
            try result.formattedContent.write(
                toFile: path,
                atomically: true,
                encoding: .utf8
            )
            return result
        } catch {
            return .failure(filePath: path, error: "Errore salvataggio: \(error.localizedDescription)")
        }
    }

    /// Verifica se il formatter è disponibile.
    func isFormatterAvailable() async -> Bool {
        await swiftFormatAdapter.isAvailable()
    }

    /// Restituisce la configurazione corrente.
    func currentConfiguration() -> FormattingServiceConfiguration {
        configuration
    }

    // MARK: - Private

    private func resolveAdapter(for filePath: String) -> FormattingAdapter {
        let ext = (filePath as NSString).pathExtension.lowercased()
        switch ext {
        case "swift":
            return swiftFormatAdapter
        default:
            return swiftFormatAdapter
        }
    }
}
