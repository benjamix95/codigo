import Foundation

enum ToolSchemaCatalog {
    static let coreEntries: [ToolSchemaEntry] =
        fileTools + runtimeTools + auditTools + indexTools + debugTools + advancedTools + planTools + integrationTools

    static var entries: [ToolSchemaEntry] {
        coreEntries + MCPNativeToolRegistry.shared.entries
    }

    static var openAIFunctionTools: [[String: Any]] {
        let core = coreEntries.map { formatOpenAI($0) }
        let mcpNative = MCPNativeToolRegistry.shared.entries.map { entry -> [String: Any] in
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
        let core = coreEntries.map { formatAnthropic($0) }
        let mcpNative = MCPNativeToolRegistry.shared.entries.map { entry -> [String: Any] in
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
