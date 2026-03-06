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

    func testLoadNormalizesPersistedWorkspacePathsAndDeduplicates() throws {
        let workspaceId = UUID()
        let base = "/tmp/ws-\(UUID().uuidString)/project"
        let dirtyWorkspace = Workspace(
            id: workspaceId,
            name: "WS",
            folderPaths: ["\(base)/", "\(base)/./", "\(base)/Sources/.."],
            excludedPaths: ["\(base)/.build/", "\(base)/.build/../.build", "   "]
        )

        let defaults = UserDefaults.standard
        defaults.set(false, forKey: "codebase_index_enabled")
        defaults.set(try JSONEncoder().encode([dirtyWorkspace]), forKey: "CoderIDE.workspaces")
        defaults.set(workspaceId.uuidString, forKey: "CoderIDE.activeWorkspaceId")

        let store = WorkspaceStore()
        guard let loaded = store.workspaces.first(where: { $0.id == workspaceId }) else {
            XCTFail("Expected workspace loaded from persistence")
            return
        }

        XCTAssertEqual(loaded.folderPaths, [canonicalPath(base)])
        XCTAssertEqual(loaded.excludedPaths, [canonicalPath("\(base)/.build")])

        guard
            let persistedData = defaults.data(forKey: "CoderIDE.workspaces"),
            let persisted = try? JSONDecoder().decode([Workspace].self, from: persistedData),
            let persistedWorkspace = persisted.first(where: { $0.id == workspaceId })
        else {
            XCTFail("Expected normalized workspace persisted back to UserDefaults")
            return
        }

        XCTAssertEqual(persistedWorkspace.folderPaths, [canonicalPath(base)])
        XCTAssertEqual(persistedWorkspace.excludedPaths, [canonicalPath("\(base)/.build")])
    }

    func testCreateNormalizesRootPathBeforePersistingInMemory() {
        let base = "/tmp/ws-\(UUID().uuidString)/project"
        let store = WorkspaceStore()

        store.create(name: "WS", rootPath: "\(base)/Sources/..//")

        XCTAssertEqual(store.workspaces.last?.folderPaths, [canonicalPath(base)])
        XCTAssertEqual(store.activeWorkspacePaths.map(\.path), [canonicalPath(base)])
    }

    func testUpdateNormalizesFolderAndExcludedPaths() {
        let workspaceId = UUID()
        let base = "/tmp/ws-\(UUID().uuidString)/project"
        let store = WorkspaceStore()
        store.workspaces = [Workspace(id: workspaceId, name: "WS", folderPaths: [], excludedPaths: [])]

        store.update(
            Workspace(
                id: workspaceId,
                name: "WS",
                folderPaths: ["\(base)/", "\(base)/Sources/.."],
                excludedPaths: ["\(base)/.build/", "\(base)/.build/../.build"]
            )
        )

        XCTAssertEqual(store.workspaces.first?.folderPaths, [canonicalPath(base)])
        XCTAssertEqual(store.workspaces.first?.excludedPaths, [canonicalPath("\(base)/.build")])
    }

    func testEffectiveExcludedPathsNormalizesAndDeduplicatesWorkspaceAndGlobalValues() {
        let workspaceId = UUID()
        let base = "/tmp/ws-\(UUID().uuidString)/project"
        let defaults = UserDefaults.standard
        defaults.set("\(base)/.build/,\(base)/.build/../.build", forKey: "codebase_index_excluded_paths")

        let store = WorkspaceStore()
        store.workspaces = [
            Workspace(
                id: workspaceId,
                name: "WS",
                folderPaths: [canonicalPath(base)],
                excludedPaths: [canonicalPath("\(base)/.build")]
            )
        ]
        store.activeWorkspaceId = workspaceId

        XCTAssertEqual(store.debugEffectiveExcludedPaths(), [canonicalPath("\(base)/.build")])
    }

    func testEffectiveExcludedPathsPreservesWorkspacePathsContainingComma() {
        let workspaceId = UUID()
        let base = "/tmp/ws-\(UUID().uuidString)/project,with-comma"
        let defaults = UserDefaults.standard
        defaults.set("/tmp/global-\(UUID().uuidString)/cache", forKey: "codebase_index_excluded_paths")

        let store = WorkspaceStore()
        store.workspaces = [
            Workspace(
                id: workspaceId,
                name: "WS",
                folderPaths: [canonicalPath(base)],
                excludedPaths: [canonicalPath("\(base)/.build")]
            )
        ]
        store.activeWorkspaceId = workspaceId

        XCTAssertEqual(
            store.debugEffectiveExcludedPaths(),
            [
                canonicalPath("\(base)/.build"),
                canonicalPath(defaults.string(forKey: "codebase_index_excluded_paths") ?? "")
            ]
        )
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
        defaults.removeObject(forKey: "codebase_index_enabled")
        defaults.removeObject(forKey: "codebase_index_excluded_paths")
    }
}
