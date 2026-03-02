import Foundation

public struct MCPServerIdentity: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: String {
        stableIdentifier
    }

    public let source: String
    public let name: String
    public let origin: String
    public let sourcePath: String?

    public init(
        source: String,
        name: String,
        origin: String,
        sourcePath: String? = nil
    ) {
        self.source = source
        self.name = name
        self.origin = origin
        self.sourcePath = sourcePath
    }

    public var stableIdentifier: String {
        let normalizedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased().replacingOccurrences(of: " ", with: "_")
        let normalizedOrigin = origin.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased().replacingOccurrences(of: " ", with: "_")
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased().replacingOccurrences(of: " ", with: "_")
        let normalizedPath = sourcePath
            .map { path in
                path.trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                    .replacingOccurrences(of: " ", with: "_")
            } ?? ""

        if normalizedPath.isEmpty {
            return "\(normalizedOrigin)|\(normalizedSource)|\(normalizedName)"
        }
        return "\(normalizedOrigin)|\(normalizedSource)|\(normalizedName)|\(normalizedPath)"
    }

    /// Identifier for logical server identity (source + origin + name), used to avoid
    /// accidental deduplication when paths differ.
    public var logicalIdentifier: String {
        let normalizedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased().replacingOccurrences(of: " ", with: "_")
        let normalizedOrigin = origin.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased().replacingOccurrences(of: " ", with: "_")
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased().replacingOccurrences(of: " ", with: "_")
        return "\(normalizedOrigin)|\(normalizedSource)|\(normalizedName)"
    }

    public static func make(
        source: String,
        name: String,
        origin: String,
        sourcePath: String? = nil
    ) -> MCPServerIdentity {
        MCPServerIdentity(
            source: source,
            name: name,
            origin: origin,
            sourcePath: sourcePath
        )
    }
}

/// Configuration for an MCP server (as in Cursor/Codex)
public struct MCPServerConfig: Codable, Identifiable {
    public let id: UUID
    public var name: String
    public var command: String
    public var args: [String]
    public var env: [String: String]
    public var enabled: Bool
    
    public init(
        id: UUID = UUID(),
        name: String = "New server",
        command: String = "",
        args: [String] = [],
        env: [String: String] = [:],
        enabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.args = args
        self.env = env
        self.enabled = enabled
    }
}
