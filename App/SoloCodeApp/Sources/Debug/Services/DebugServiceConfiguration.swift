import Foundation

struct DebugServiceConfiguration: Sendable {
    let debugServiceEnabled: Bool
    let debugDAPLLDBEnabled: Bool

    var nativeDebuggerEnabled: Bool {
        debugServiceEnabled && debugDAPLLDBEnabled
    }

    var disabledReason: String? {
        if !debugServiceEnabled {
            return "Debug service disabilitato (feature flag `debug_service_enabled=false`)."
        }
        if !debugDAPLLDBEnabled {
            return "Adapter LLDB/DAP disabilitato (feature flag `debug_dap_lldb_enabled=false`)."
        }
        return nil
    }

    static func load(from defaults: UserDefaults = .standard) -> DebugServiceConfiguration {
        let debugServiceEnabled = defaults.object(forKey: "debug_service_enabled") as? Bool ?? true
        let debugDAPLLDBEnabled = defaults.object(forKey: "debug_dap_lldb_enabled") as? Bool ?? true
        return DebugServiceConfiguration(
            debugServiceEnabled: debugServiceEnabled,
            debugDAPLLDBEnabled: debugDAPLLDBEnabled
        )
    }
}
