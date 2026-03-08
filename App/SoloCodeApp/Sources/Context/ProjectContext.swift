import Foundation
import CoderEngine

enum ProjectContextKind: String, Codable, Sendable {
    case workspace
    case singleProject
}

struct ProjectContext: Identifiable, Codable, Sendable {
    let id: UUID
    var kind: ProjectContextKind
    var name: String
    var folderPaths: [String]
    var excludedPaths: [String]
    var isPinned: Bool
    var createdAt: Date
    var updatedAt: Date
    var lastActiveFolderPath: String?

    init(
        id: UUID = UUID(),
        kind: ProjectContextKind,
        name: String,
        folderPaths: [String],
        excludedPaths: [String] = [],
        isPinned: Bool,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        lastActiveFolderPath: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.folderPaths = folderPaths
        self.excludedPaths = excludedPaths
        self.isPinned = isPinned
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastActiveFolderPath = lastActiveFolderPath ?? folderPaths.first
    }

    var activeFolderPath: String? {
        if let lastActiveFolderPath, folderPaths.contains(lastActiveFolderPath) {
            return lastActiveFolderPath
        }
        return folderPaths.first
    }

    static func fromWorkspace(_ workspace: Workspace) -> ProjectContext {
        ProjectContext(
            id: workspace.id,
            kind: .workspace,
            name: workspace.name,
            folderPaths: workspace.folderPaths,
            excludedPaths: workspace.excludedPaths,
            isPinned: true,
            lastActiveFolderPath: workspace.folderPaths.first
        )
    }
}
