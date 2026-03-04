import Foundation

// MARK: - Linting Service Configuration

struct LintingServiceConfiguration: Sendable {
    let lintingEnabled: Bool
    let lintOnSave: Bool
    let lintOnType: Bool
    let swiftLintPath: String
    let autoFixEnabled: Bool

    var isEnabled: Bool { lintingEnabled }

    var disabledReason: String? {
        if !lintingEnabled {
            return "Linting disabilitato (feature flag `linting_enabled=false`)."
        }
        return nil
    }

    static func load(from defaults: UserDefaults = .standard) -> LintingServiceConfiguration {
        let enabled = defaults.object(forKey: "linting_enabled") as? Bool ?? true
        let onSave = defaults.object(forKey: "lint_on_save") as? Bool ?? true
        let onType = defaults.object(forKey: "lint_on_type") as? Bool ?? false
        let autoFix = defaults.object(forKey: "lint_auto_fix") as? Bool ?? false
        let swiftLintPath = defaults.string(forKey: "swiftlint_path")?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return LintingServiceConfiguration(
            lintingEnabled: enabled,
            lintOnSave: onSave,
            lintOnType: onType,
            swiftLintPath: (swiftLintPath?.isEmpty == false) ? swiftLintPath! : "swiftlint",
            autoFixEnabled: autoFix
        )
    }
}
