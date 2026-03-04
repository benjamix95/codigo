import Foundation

enum ExtensionCapability: String, Codable, CaseIterable, Hashable, Sendable {
    case readWorkspace = "workspace.read"
    case readOnlyTools = "tools.read_only"
    case writeWorkspace = "workspace.write"
    case executeCommands = "commands.execute"
    case networkAccess = "network.access"

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        switch normalized {
        case "workspace.read", "read":
            self = .readWorkspace
        case "tools.read_only":
            self = .readOnlyTools
        case "workspace.write", "write", "edit":
            self = .writeWorkspace
        case "commands.execute", "bash", "subagent":
            self = .executeCommands
        case "network.access", "web":
            self = .networkAccess
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Capability extension non supportata: \(raw)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct ExtensionManifest: Codable, Hashable, Sendable {
    let id: String
    let name: String
    let version: String
    let entryPoint: String
    let capabilities: [ExtensionCapability]
    let exposedTools: [String]
    let minimumIDEVersion: String?

    private enum CodingKeys: String, CodingKey {
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

    init(
        id: String,
        name: String,
        version: String,
        entryPoint: String,
        capabilities: [ExtensionCapability],
        exposedTools: [String],
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.version = try container.decode(String.self, forKey: .version)
        if let entryPoint = try container.decodeIfPresent(String.self, forKey: .entryPoint) {
            self.entryPoint = entryPoint
        } else {
            self.entryPoint = try container.decode(String.self, forKey: .entrypoint)
        }
        self.capabilities = try container.decode([ExtensionCapability].self, forKey: .capabilities)
        if let exposed = try container.decodeIfPresent([String].self, forKey: .exposedTools) {
            self.exposedTools = exposed
        } else {
            self.exposedTools = try container.decodeIfPresent([String].self, forKey: .allowedTools) ?? []
        }
        self.minimumIDEVersion = try container.decodeIfPresent(String.self, forKey: .minimumIDEVersion)
    }

    func encode(to encoder: Encoder) throws {
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

struct ExtensionToolRequest: Sendable {
    let tool: String
    let payload: [String: String]
}

struct ExtensionToolResponse: Sendable, Equatable {
    let output: String
    let metadata: [String: String]

    init(output: String, metadata: [String: String] = [:]) {
        self.output = output
        self.metadata = metadata
    }
}

struct ExtensionRuntimeContext: Sendable {
    let workspaceRoots: [String]
    let allowedCapabilities: Set<ExtensionCapability>
    let grantedCapabilities: Set<ExtensionCapability>

    func isCapabilityAllowed(_ capability: ExtensionCapability) -> Bool {
        grantedCapabilities.contains(capability) && allowedCapabilities.contains(capability)
    }
}

protocol IDEExtensionPlugin: Sendable {
    var manifest: ExtensionManifest { get }
    func onLoad(context: ExtensionRuntimeContext) async throws
    func onUnload(context: ExtensionRuntimeContext) async
    func handle(request: ExtensionToolRequest, context: ExtensionRuntimeContext) async throws -> ExtensionToolResponse
}
