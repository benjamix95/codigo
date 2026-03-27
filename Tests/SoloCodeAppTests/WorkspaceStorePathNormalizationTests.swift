import XCTest
@testable import CoderIDE
@testable import CoderEngine

@MainActor
final class WorkspaceStorePathNormalizationTests: XCTestCase {
    private var workspaceManifestTempRoot: URL?

    override func setUp() {
        super.setUp()
        clearWorkspacePersistence()
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent("workspace-manifests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        workspaceManifestTempRoot = temp
        WorkspaceStore.workspaceManifestDirectoryOverrideURL = temp
    }

    override func tearDown() {
        clearWorkspacePersistence()
        WorkspaceStore.workspaceManifestDirectoryOverrideURL = nil
        if let workspaceManifestTempRoot {
            try? FileManager.default.removeItem(at: workspaceManifestTempRoot)
        }
        workspaceManifestTempRoot = nil
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

    func testSaveWritesWorkspaceManifestJSONFile() throws {
        let baseA = FileManager.default.temporaryDirectory
            .appendingPathComponent("ws-\(UUID().uuidString)-a", isDirectory: true)
        let baseB = FileManager.default.temporaryDirectory
            .appendingPathComponent("ws-\(UUID().uuidString)-b", isDirectory: true)
        try FileManager.default.createDirectory(at: baseA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: baseB, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: baseA)
            try? FileManager.default.removeItem(at: baseB)
        }

        let workspace = Workspace(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            name: "Client Workspace",
            folderPaths: [baseA.path, baseB.path],
            excludedPaths: [baseA.appendingPathComponent(".build").path]
        )
        let store = WorkspaceStore()
        store.workspaces = [workspace]

        store.save()

        let manifestDir = try XCTUnwrap(WorkspaceStore.workspaceManifestDirectoryOverrideURL)
        let files = try FileManager.default.contentsOfDirectory(at: manifestDir, includingPropertiesForKeys: nil)
        let manifest = try XCTUnwrap(files.first(where: { $0.lastPathComponent.contains("client-workspace") }))
        let data = try Data(contentsOf: manifest)
        let decoded = try JSONDecoder().decode(WorkspaceFileDocument.self, from: data)

        XCTAssertEqual(decoded.id, workspace.id)
        XCTAssertEqual(decoded.name, workspace.name)
        XCTAssertEqual(decoded.folders, workspace.folderPaths)
        XCTAssertEqual(decoded.excludedPaths, workspace.excludedPaths)
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

    func testIndexerExcludedPathsConvertsAbsolutePathsToWorkspaceRelativePaths() {
        let store = WorkspaceStore()
        let base = canonicalPath("/tmp/ws-\(UUID().uuidString)/project")
        let other = canonicalPath("/tmp/ws-\(UUID().uuidString)/other")

        let relative = store.indexerExcludedPaths(
            for: [URL(fileURLWithPath: base), URL(fileURLWithPath: other)],
            excludedPaths: [
                "\(base)/.build/",
                "\(base)/Sources/Generated",
                other,
                "/tmp/outside-scope"
            ]
        )

        XCTAssertEqual(
            relative,
            [
                "project/.build",
                "project/Sources/Generated",
                "other"
            ]
        )
    }

    func testIndexActiveWorkspaceCancelsStaleIndexingTaskBeforeClear() async throws {
        let workspaceRoot = URL(fileURLWithPath: canonicalPath("/tmp/ws-\(UUID().uuidString)/project"), isDirectory: true)
        try FileManager.default.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspaceRoot) }

        for index in 0..<400 {
            let fileURL = workspaceRoot.appendingPathComponent("File\(index).swift")
            try "struct Type\(index) { let value = \(index) }\n".write(
                to: fileURL,
                atomically: true,
                encoding: .utf8
            )
        }

        let defaults = UserDefaults.standard
        defaults.set(true, forKey: "codebase_index_enabled")

        let workspaceId = UUID()
        let store = WorkspaceStore()
        store.workspaces = [
            Workspace(
                id: workspaceId,
                name: "WS",
                folderPaths: [workspaceRoot.path(percentEncoded: false)],
                excludedPaths: []
            )
        ]
        store.activeWorkspaceId = workspaceId

        store.indexActiveWorkspace()
        defaults.set(false, forKey: "codebase_index_enabled")
        store.indexActiveWorkspace()

        for _ in 0..<40 {
            if !store.debugIndexingState().hasIndexingTask {
                break
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        let status = await store.codebaseIndex.status()
        XCTAssertEqual(status.status, .idle)
        XCTAssertTrue(status.workspacePaths.isEmpty)
        XCTAssertEqual(status.totalSourceFiles, 0)
        XCTAssertFalse(store.debugIndexingState().hasWatcher)
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
