import Foundation

enum ToolSchemaCatalog {
    static let coreEntries: [ToolSchemaEntry] =
        fileTools + runtimeTools + auditTools + indexTools + debugTools + advancedTools + planTools + integrationTools

    private static let runtimePreferredIDEStateToolNames: Set<String> = [
        "policy_ack",
        "activate_debug_mode",
        "activate_plan_mode",
        "debug_set_phase",
        "debug_request_user",
        "debug_resolve",
        "show_task_panel",
        "show_swarm_panel",
    ]

    private static func providerVisibleCatalog() -> (core: [ToolSchemaEntry], native: [ToolSchemaEntry]) {
        let nativeEntries = MCPNativeToolRegistry.shared.entries
        guard !nativeEntries.isEmpty else {
            return (coreEntries, [])
        }

        let canonicalRegistry = CoderIDECanonicalToolRegistry.shared
        let nativeRuntimeNames = Set(
            nativeEntries.compactMap { entry in
                canonicalRegistry.runtimeName(forMCPName: entry.name)?.lowercased()
            }
        )
        let runtimePreferred = nativeRuntimeNames.intersection(runtimePreferredIDEStateToolNames)
        let mcpPreferred = nativeRuntimeNames.subtracting(runtimePreferred)

        let filteredCore = coreEntries.filter { entry in
            !mcpPreferred.contains(entry.name.lowercased())
        }
        let filteredNative = nativeEntries.filter { entry in
            guard let runtimeName = canonicalRegistry.runtimeName(forMCPName: entry.name)?.lowercased() else {
                return true
            }
            return !runtimePreferred.contains(runtimeName)
        }
        return (filteredCore, filteredNative)
    }

    static var entries: [ToolSchemaEntry] {
        coreEntries + MCPNativeToolRegistry.shared.entries
    }

    static var openAIFunctionTools: [[String: Any]] {
        let visible = providerVisibleCatalog()
        let core = visible.core.map { formatOpenAI($0) }
        let mcpNative = visible.native.map { entry -> [String: Any] in
            if let rawSchema = MCPNativeToolRegistry.shared.rawSchema(for: entry.name) {
                return [
                    "type": "function",
                    "function": [
                        "name": entry.name,
                        "description": entry.description,
                        "parameters": rawSchema,
                    ] as [String: Any],
                ]
            }
            return formatOpenAI(entry)
        }
        return core + mcpNative
    }

    static var anthropicTools: [[String: Any]] {
        let visible = providerVisibleCatalog()
        let core = visible.core.map { formatAnthropic($0) }
        let mcpNative = visible.native.map { entry -> [String: Any] in
            if let rawSchema = MCPNativeToolRegistry.shared.rawSchema(for: entry.name) {
                return [
                    "name": entry.name,
                    "description": entry.description,
                    "input_schema": rawSchema,
                ] as [String: Any]
            }
            return formatAnthropic(entry)
        }
        return core + mcpNative
    }

    private static func formatOpenAI(_ entry: ToolSchemaEntry) -> [String: Any] {
        [
            "type": "function",
            "function": [
                "name": entry.name,
                "description": entry.description,
                "parameters": [
                    "type": "object",
                    "properties": entry.properties,
                    "required": entry.required,
                ],
            ] as [String: Any],
        ]
    }

    private static func formatAnthropic(_ entry: ToolSchemaEntry) -> [String: Any] {
        [
            "name": entry.name,
            "description": entry.description,
            "input_schema": [
                "type": "object",
                "properties": entry.properties,
                "required": entry.required,
            ],
        ]
    }
}

public enum RuntimeTransportToolDefinitions {
    public static func openAICompatibleJSON() -> String? {
        jsonString(from: ToolSchemaCatalog.openAIFunctionTools)
    }

    public static func anthropicJSON() -> String? {
        jsonString(from: ToolSchemaCatalog.anthropicTools)
    }

    private static func jsonString(from value: [[String: Any]]) -> String? {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return json
    }
}
