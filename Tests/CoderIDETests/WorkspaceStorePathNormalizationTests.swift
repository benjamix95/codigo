import XCTest
@testable import CoderIDE
@testable import CoderEngine

@MainActor
final class WorkspaceStorePathNormalizationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        clearWorkspacePersistence()
    }

    override func tearDown() {
        clearWorkspacePersistence()
        super.tearDown()
    }

    func testAddFolderNormalizesEquivalentPathsAndPreventsDuplicates() {
        let workspaceId = UUID()
        let store = WorkspaceStore()
        store.workspaces = [Workspace(id: workspaceId, name: "WS", folderPaths: [], excludedPaths: [])]

        let base = "/tmp/ws-\(UUID().uuidString)/project"
        let withTrailingSlash = "\(base)/"
        let equivalent = "\(base)/Sources/../"

        store.addFolder(to: workspaceId, path: withTrailingSlash)
        store.addFolder(to: workspaceId, path: equivalent)

        let folders = store.workspaces.first(where: { $0.id == workspaceId })?.folderPaths ?? []
        XCTAssertEqual(folders, [canonicalPath(base)])
    }

    func testRemoveFolderSupportsEquivalentPathAndIsIdempotent() {
        let workspaceId = UUID()
        let base = "/tmp/ws-\(UUID().uuidString)/project"
        let store = WorkspaceStore()
        store.workspaces = [
            Workspace(
                id: workspaceId,
                name: "WS",
                folderPaths: [canonicalPath(base)],
                excludedPaths: []
            )
        ]

        store.removeFolder(from: workspaceId, path: "\(base)/./")
        store.removeFolder(from: workspaceId, path: "\(base)/")

        let folders = store.workspaces.first(where: { $0.id == workspaceId })?.folderPaths ?? []
        XCTAssertTrue(folders.isEmpty)
    }

    func testAddExclusionNormalizesEquivalentPathsAndPreventsDuplicates() {
        let workspaceId = UUID()
        let store = WorkspaceStore()
        store.workspaces = [Workspace(id: workspaceId, name: "WS", folderPaths: [], excludedPaths: [])]

        let base = "/tmp/ws-\(UUID().uuidString)/project/.build"
        let withTrailingSlash = "\(base)/"
        let equivalent = "\(base)/../.build"

        store.addExclusion(to: workspaceId, path: withTrailingSlash)
        store.addExclusion(to: workspaceId, path: equivalent)

        let exclusions = store.workspaces.first(where: { $0.id == workspaceId })?.excludedPaths ?? []
        XCTAssertEqual(exclusions, [canonicalPath(base)])
    }

    func testRemoveExclusionSupportsEquivalentPathAndIsIdempotent() {
        let workspaceId = UUID()
        let base = "/tmp/ws-\(UUID().uuidString)/project/.swiftpm"
        let store = WorkspaceStore()
        store.workspaces = [
            Workspace(
                id: workspaceId,
                name: "WS",
                folderPaths: [],
                excludedPaths: [canonicalPath(base)]
            )
        ]

        store.removeExclusion(from: workspaceId, path: "\(base)/./")
        store.removeExclusion(from: workspaceId, path: "\(base)/")

        let exclusions = store.workspaces.first(where: { $0.id == workspaceId })?.excludedPaths ?? []
        XCTAssertTrue(exclusions.isEmpty)
    }

    private func canonicalPath(_ rawPath: String) -> String {
        URL(fileURLWithPath: rawPath)
            .standardizedFileURL
            .path(percentEncoded: false)
    }

    private func clearWorkspacePersistence() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "CoderIDE.workspaces")
        defaults.removeObject(forKey: "CoderIDE.activeWorkspaceId")
    }
}
