import Foundation

extension UnifiedToolRuntime {
    static func shouldPreferRustAlias(for toolName: String) -> Bool {
        CoderIDECanonicalToolRegistry.shared.record(forRuntimeName: toolName) != nil
    }

    func preferredRustAliasRoute(for toolName: String) -> (serverId: String, toolName: String)? {
        guard Self.shouldPreferRustAlias(for: toolName) else { return nil }
        if let aliasRoute = MCPNativeToolRegistry.shared.aliasRoute(for: toolName) {
            return aliasRoute
        }
        return MCPNativeToolRegistry.shared.routing["coderide_\(toolName)"]
    }
}
