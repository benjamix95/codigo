import Foundation

public enum PluginCapability: String, Codable, CaseIterable, Sendable {
    case read
    case edit
    case write
    case bash
    case web
    case mcp
    case git
    case debug
    case subagent

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        switch normalized {
        case "read", "workspace.read", "tools.read_only":
            self = .read
        case "edit", "workspace.edit":
            self = .edit
        case "write", "workspace.write":
            self = .write
        case "bash", "commands.execute":
            self = .bash
        case "web", "network.access":
            self = .web
        case "mcp":
            self = .mcp
        case "git":
            self = .git
        case "debug":
            self = .debug
        case "subagent":
            self = .subagent
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Capability plugin non supportata: \(raw)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct IDEPluginManifest: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let version: String
    public let entryPoint: String
    public let capabilities: [PluginCapability]
    public let exposedTools: [String]
    public let minimumIDEVersion: String?

    // Compat legacy API.
    public var entrypoint: String { entryPoint }
    public var allowedTools: [String] { exposedTools }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case version
        case entryPoint
        case entrypoint
        case capabilities
        case exposedTools
        case allowedTools
        case minimumIDEVersion
    }

    public init(
        id: String,
        name: String,
        version: String,
        entryPoint: String,
        capabilities: [PluginCapability],
        exposedTools: [String] = [],
        minimumIDEVersion: String? = nil
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.entryPoint = entryPoint
        self.capabilities = capabilities
        self.exposedTools = exposedTools
        self.minimumIDEVersion = minimumIDEVersion
    }

    public init(
        id: String,
        name: String,
        version: String,
        entrypoint: String,
        capabilities: [PluginCapability],
        allowedTools: [String] = [],
        minimumIDEVersion: String? = nil
    ) {
        self.init(
            id: id,
            name: name,
            version: version,
            entryPoint: entrypoint,
            capabilities: capabilities,
            exposedTools: allowedTools,
            minimumIDEVersion: minimumIDEVersion
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.version = try container.decode(String.self, forKey: .version)
        self.entryPoint = try container.decodeAliasString(primary: .entryPoint, fallback: .entrypoint)
        self.capabilities = try container.decode([PluginCapability].self, forKey: .capabilities)
        self.exposedTools = try container.decodeAliasStringArray(primary: .exposedTools, fallback: .allowedTools)
        self.minimumIDEVersion = try container.decodeIfPresent(String.self, forKey: .minimumIDEVersion)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(version, forKey: .version)
        try container.encode(entryPoint, forKey: .entryPoint)
        try container.encode(capabilities, forKey: .capabilities)
        if !exposedTools.isEmpty {
            try container.encode(exposedTools, forKey: .exposedTools)
        }
        try container.encodeIfPresent(minimumIDEVersion, forKey: .minimumIDEVersion)
    }
}

public struct IDEPluginDescriptor: Sendable, Equatable {
    public let manifest: IDEPluginManifest
    public let rootPath: String
    public let loadedAt: Date
}

public enum IDEPluginRuntimeError: Error, LocalizedError {
    case invalidManifest(String)
    case pluginAlreadyLoaded(String)
    case pluginNotLoaded(String)
    case manifestNotFound(String)
    case minimumIDEVersionNotSatisfied(required: String, current: String)

    public var errorDescription: String? {
        switch self {
        case .invalidManifest(let detail):
            return "Manifest plugin non valido: \(detail)"
        case .pluginAlreadyLoaded(let id):
            return "Plugin già caricato: \(id)"
        case .pluginNotLoaded(let id):
            return "Plugin non caricato: \(id)"
        case .manifestNotFound(let path):
            return "Manifest plugin non trovato: \(path)"
        case .minimumIDEVersionNotSatisfied(let required, let current):
            return "Plugin richiede IDE >= \(required), versione corrente: \(current)"
        }
    }
}

private extension KeyedDecodingContainer where Key == IDEPluginManifest.CodingKeys {
    func decodeAliasString(
        primary: Key,
        fallback: Key
    ) throws -> String {
        if let value = try decodeIfPresent(String.self, forKey: primary) {
            return value
        }
        return try decode(String.self, forKey: fallback)
    }

    func decodeAliasStringArray(
        primary: Key,
        fallback: Key
    ) throws -> [String] {
        if let value = try decodeIfPresent([String].self, forKey: primary) {
            return value
        }
        return try decodeIfPresent([String].self, forKey: fallback) ?? []
    }
}
