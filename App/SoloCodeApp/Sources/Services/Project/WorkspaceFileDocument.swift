import CoderEngine
import Foundation

struct WorkspaceFileDocument: Codable, Equatable {
    let id: UUID
    let name: String
    let folders: [String]
    let excludedPaths: [String]

    init(workspace: Workspace) {
        self.id = workspace.id
        self.name = workspace.name
        self.folders = workspace.folderPaths
        self.excludedPaths = workspace.excludedPaths
    }
}
