import Foundation

/// Workspace con cartelle incluse e sottocartelle escluse
public struct Workspace: Identifiable, Codable, Sendable {
    public var id: UUID
    public var name: String
    public var folderPaths: [String]
    public var excludedPaths: [String]
    
    /// Primo path per compatibilità (Editor, Terminal, ChatPanel)
    public var rootPath: String {
        folderPaths.first ?? ""
    }
    
    public var rootURL: URL? {
        guard !rootPath.isEmpty else { return nil }
        return URL(fileURLWithPath: rootPath)
    }

    public init(id: UUID = UUID(), name: String, folderPaths: [String] = [], excludedPaths: [String] = []) {
        self.id = id
        self.name = name
        self.folderPaths = folderPaths
        self.excludedPaths = excludedPaths
    }
    
    /// Inizializzatore di convenienza per singola cartella (retrocompat)
    public init(id: UUID = UUID(), name: String, rootPath: String, excludedPaths: [String] = []) {
        self.id = id
        self.name = name
        self.folderPaths = rootPath.isEmpty ? [] : [rootPath]
        self.excludedPaths = excludedPaths
    }
    
    // MARK: - Codable migration
    private enum CodingKeys: String, CodingKey {
        case id, name, folderPaths, excludedPaths, rootPath
    }
    
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        excludedPaths = (try? c.decode([String].self, forKey: .excludedPaths)) ?? []
        
        if let folders = try? c.decode([String].self, forKey: .folderPaths), !folders.isEmpty {
            folderPaths = folders
        } else if let legacyRoot = try? c.decode(String.self, forKey: .rootPath), !legacyRoot.isEmpty {
            folderPaths = [legacyRoot]
        } else {
            folderPaths = []
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(folderPaths, forKey: .folderPaths)
        try c.encode(excludedPaths, forKey: .excludedPaths)
    }
}
