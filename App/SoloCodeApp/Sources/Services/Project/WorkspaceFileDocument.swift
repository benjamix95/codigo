import CoderEngine
import Foundation

struct WorkspaceFolderEntry: Codable, Equatable {
    let path: String
}

struct WorkspaceFileDocument: Codable, Equatable {
    let id: UUID
    let name: String
    let folders: [WorkspaceFolderEntry]
    let excludedPaths: [String]

    init(workspace: Workspace) {
        self.id = workspace.id
        self.name = workspace.name
        self.folders = workspace.folderPaths.map { WorkspaceFolderEntry(path: $0) }
        self.excludedPaths = workspace.excludedPaths
    }
}
