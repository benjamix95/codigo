import Foundation

// MARK: - Formatting Service Configuration

struct FormattingServiceConfiguration: Sendable {
    let formattingEnabled: Bool
    let formatOnSave: Bool
    let swiftFormatPath: String
    let prettierPath: String
    let defaultFormatter: FormatterType

    var isEnabled: Bool { formattingEnabled }

    var disabledReason: String? {
        if !formattingEnabled {
            return "Formattazione disabilitata (feature flag `formatting_enabled=false`)."
        }
        return nil
    }

    static func load(from defaults: UserDefaults = .standard) -> FormattingServiceConfiguration {
        let enabled = defaults.object(forKey: "formatting_enabled") as? Bool ?? true
        let onSave = defaults.object(forKey: "format_on_save") as? Bool ?? false
        let swiftFormatPath = defaults.string(forKey: "swift_format_path")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let prettierPath = defaults.string(forKey: "prettier_path")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let defaultFormatterRaw = defaults.string(forKey: "default_formatter") ?? "swift-format"

        return FormattingServiceConfiguration(
            formattingEnabled: enabled,
            formatOnSave: onSave,
            swiftFormatPath: (swiftFormatPath?.isEmpty == false) ? swiftFormatPath! : "swift-format",
            prettierPath: (prettierPath?.isEmpty == false) ? prettierPath! : "prettier",
            defaultFormatter: FormatterType(rawValue: defaultFormatterRaw) ?? .swiftFormat
        )
    }
}
