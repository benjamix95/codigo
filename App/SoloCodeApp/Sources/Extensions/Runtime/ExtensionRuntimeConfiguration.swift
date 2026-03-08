import Foundation

struct ExtensionRuntimeConfiguration: Sendable {
    let runtimeEnabled: Bool
    let allowedCapabilities: Set<ExtensionCapability>
    let currentIDEVersion: String

    init(
        runtimeEnabled: Bool,
        allowedCapabilities: Set<ExtensionCapability>,
        currentIDEVersion: String = "1.0.0"
    ) {
        self.runtimeEnabled = runtimeEnabled
        self.allowedCapabilities = allowedCapabilities
        self.currentIDEVersion = currentIDEVersion
    }

    static func load(from defaults: UserDefaults = .standard) -> ExtensionRuntimeConfiguration {
        let runtimeEnabled = defaults.object(forKey: "extensions_runtime_enabled") as? Bool ?? true
        let configured = defaults.string(forKey: "extensions_runtime_allowed_capabilities")
            .map { raw in
                raw
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .compactMap(ExtensionCapability.init(rawValue:))
            } ?? []
        let currentIDEVersion = defaults.string(forKey: "extensions_runtime_current_ide_version")
            ?? (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
            ?? "1.0.0"

        let fallbackDefault: Set<ExtensionCapability> = [.readWorkspace, .readOnlyTools]
        let allowed = configured.isEmpty ? fallbackDefault : Set(configured)
        return ExtensionRuntimeConfiguration(
            runtimeEnabled: runtimeEnabled,
            allowedCapabilities: allowed,
            currentIDEVersion: currentIDEVersion
        )
    }
}
