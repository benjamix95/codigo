import Foundation

struct ToolSchemaEntry: @unchecked Sendable {
    let name: String
    let description: String
    let properties: [String: [String: Any]]
    let required: [String]
}

/// Stores native MCP tool definitions alongside the routing table.
/// Thread-safe via NSLock for concurrent access from providers + runtime.
final class MCPNativeToolRegistry: @unchecked Sendable {
    static let shared = MCPNativeToolRegistry()

    private let lock = NSLock()
    private var _descriptors: [MCPToolDescriptor] = []
    private var _entries: [ToolSchemaEntry] = []
    private var _routing: [String: (serverId: String, toolName: String)] = [:]
    private var _aliasRouting: [String: (serverId: String, toolName: String)] = [:]
    private var _rawSchemas: [String: [String: Any]] = [:]
    private var _sourceFingerprint = ""

    var entries: [ToolSchemaEntry] {
        lock.lock()
        defer { lock.unlock() }
        return _entries
    }

    var routing: [String: (serverId: String, toolName: String)] {
        lock.lock()
        defer { lock.unlock() }
        return _routing
    }

    func aliasRoute(for toolName: String) -> (serverId: String, toolName: String)? {
        lock.lock()
        defer { lock.unlock() }
        return _aliasRouting[toolName]
    }

    /// Full JSON Schema dict for a native MCP tool, used in OpenAI/Anthropic function params.
    func rawSchema(for functionName: String) -> [String: Any]? {
        lock.lock()
        defer { lock.unlock() }
        return _rawSchemas[functionName]
    }

    func hasTools() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return !_entries.isEmpty
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        _descriptors.removeAll()
        _entries.removeAll()
        _routing.removeAll()
        _aliasRouting.removeAll()
        _rawSchemas.removeAll()
        _sourceFingerprint = ""
    }

    /// Register MCP tools as native function tools.
    /// Creates normalized function names and routing entries.
    @discardableResult
    func register(tools: [MCPToolDescriptor]) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return rebuildLocked(with: tools)
    }

    @discardableResult
    func mergeRegister(tools: [MCPToolDescriptor]) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !tools.isEmpty else { return false }

        var mergedByKey: [String: MCPToolDescriptor] = [:]
        for descriptor in _descriptors {
            mergedByKey[Self.descriptorIdentityKey(for: descriptor)] = descriptor
        }
        for descriptor in tools {
            mergedByKey[Self.descriptorIdentityKey(for: descriptor)] = descriptor
        }
        let merged = mergedByKey.values.sorted { lhs, rhs in
            if lhs.serverId != rhs.serverId { return lhs.serverId < rhs.serverId }
            if lhs.name != rhs.name { return lhs.name < rhs.name }
            return lhs.schema < rhs.schema
        }
        return rebuildLocked(with: merged)
    }

    private func rebuildLocked(with tools: [MCPToolDescriptor]) -> Bool {
        let fingerprint = Self.descriptorFingerprint(for: tools)
        if fingerprint == _sourceFingerprint {
            return false
        }

        _descriptors = tools
        _entries.removeAll()
        _routing.removeAll()
        _aliasRouting.removeAll()
        _rawSchemas.removeAll()
        _sourceFingerprint = fingerprint

        var nameCount: [String: Int] = [:]
        for tool in tools {
            nameCount[tool.name, default: 0] += 1
        }

        let sortedTools = tools.sorted { lhs, rhs in
            if lhs.serverId != rhs.serverId { return lhs.serverId < rhs.serverId }
            if lhs.name != rhs.name { return lhs.name < rhs.name }
            return lhs.schema < rhs.schema
        }
        var usedFunctionNames = Set<String>()

        for tool in sortedTools {
            let needsPrefix = nameCount[tool.name, default: 0] > 1
            let baseFunctionName = Self.normalizeFunctionName(
                serverName: tool.serverName,
                toolName: tool.name,
                needsPrefix: needsPrefix
            )
            let functionName = Self.resolveUniqueFunctionName(
                base: baseFunctionName,
                serverId: tool.serverId,
                toolName: tool.name,
                usedNames: &usedFunctionNames
            )

            let simplifiedProps = Self.extractSimplifiedProperties(from: tool)
            let trustedDescription = Self.safeMCPToolDescription(serverName: tool.serverName)

            _entries.append(ToolSchemaEntry(
                name: functionName,
                description: trustedDescription,
                properties: simplifiedProps.properties,
                required: simplifiedProps.required
            ))

            _routing[functionName] = (serverId: tool.serverId, toolName: tool.name)
            if let alias = Self.runtimeAlias(for: tool.name),
               _aliasRouting[alias] == nil {
                _aliasRouting[alias] = (serverId: tool.serverId, toolName: tool.name)
            }

            if let schemaDict = tool.inputSchemaDict {
                _rawSchemas[functionName] = schemaDict
            }
        }
        return true
    }

    private static func descriptorIdentityKey(for descriptor: MCPToolDescriptor) -> String {
        "\(descriptor.serverId)|\(descriptor.name)|\(descriptor.schema)"
    }

    private static func runtimeAlias(for toolName: String) -> String? {
        CoderIDECanonicalToolRegistry.shared.runtimeName(forMCPName: toolName)
    }

    /// MCP tool metadata comes from external servers and must not be injected
    /// verbatim into model-visible prompt/tool description fields.
    private static func safeMCPToolDescription(serverName: String) -> String {
        "[\(serverName)] Tool provided by MCP server. Refer to schema/arguments for usage."
    }

    /// Normalize server/tool names into a valid OpenAI function name.
    /// Format: `toolname` if unique, `servername_toolname` if ambiguous.
    /// Must match `^[a-zA-Z0-9_-]{1,64}$`.
    private static func normalizeFunctionName(serverName: String, toolName: String, needsPrefix: Bool) -> String {
        let normalizedServer = serverName
            .replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_-"))
        let normalizedTool = toolName
            .replacingOccurrences(of: "[^a-zA-Z0-9_-]", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_-"))

        let raw = needsPrefix ? "\(normalizedServer)_\(normalizedTool)" : normalizedTool
        let clamped = String(raw.prefix(64))
        return clamped.isEmpty ? "mcp_tool" : clamped
    }

    private static func resolveUniqueFunctionName(
        base: String,
        serverId: String,
        toolName: String,
        usedNames: inout Set<String>
    ) -> String {
        let normalizedBase = base.isEmpty ? "mcp_tool" : String(base.prefix(64))
        if usedNames.insert(normalizedBase).inserted {
            return normalizedBase
        }

        let stableSuffix = deterministicSuffix(seed: "\(serverId)|\(toolName)|\(normalizedBase)")
        var attempt = 0
        while true {
            let suffix = attempt == 0 ? stableSuffix : "\(stableSuffix)\(attempt)"
            let maxBaseLength = max(1, 64 - suffix.count - 1)
            let truncatedBase = String(normalizedBase.prefix(maxBaseLength))
            let candidate = "\(truncatedBase)_\(suffix)"
            if usedNames.insert(candidate).inserted {
                return candidate
            }
            attempt += 1
        }
    }

    private static func deterministicSuffix(seed: String) -> String {
        var hash: UInt64 = 1469598103934665603
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        let base36 = String(hash, radix: 36)
        let suffix = String(base36.suffix(8))
        return suffix.isEmpty ? "0" : suffix
    }

    private static func descriptorFingerprint(for tools: [MCPToolDescriptor]) -> String {
        let lines = tools
            .sorted { lhs, rhs in
                if lhs.serverId != rhs.serverId { return lhs.serverId < rhs.serverId }
                if lhs.name != rhs.name { return lhs.name < rhs.name }
                return lhs.schema < rhs.schema
            }
            .map { descriptor in
                "\(descriptor.serverId)|\(descriptor.serverName)|\(descriptor.name)|\(descriptor.description)|\(descriptor.schema)"
            }
        return lines.joined(separator: "\n")
    }

    /// Extract simplified properties from an MCP tool descriptor.
    /// Flattens complex JSON Schema into [String: [String: String]] for ToolSchemaEntry.
    private static func extractSimplifiedProperties(from tool: MCPToolDescriptor) -> (properties: [String: [String: Any]], required: [String]) {
        guard let schema = tool.inputSchemaDict,
              let props = schema["properties"] as? [String: Any] else {
            return (properties: [:], required: [])
        }

        var simplified: [String: [String: Any]] = [:]
        for (key, value) in props {
            if let propDict = value as? [String: Any] {
                var entry: [String: Any] = [:]
                if let type = propDict["type"] as? String {
                    entry["type"] = type
                } else {
                    entry["type"] = "string"
                }
                if let desc = propDict["description"] as? String {
                    entry["description"] = desc
                }
                if let enumValues = propDict["enum"] as? [String] {
                    entry["enum"] = enumValues
                }
                simplified[key] = entry
            } else {
                simplified[key] = ["type": "string"]
            }
        }

        let required = (schema["required"] as? [String]) ?? []
        return (properties: simplified, required: required)
    }
}
