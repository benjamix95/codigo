import XCTest
@testable import CoderIDE

@MainActor
final class WorkspaceStoreContextSyncTests: XCTestCase {
    override func setUp() {
        super.setUp()
        clearWorkspacePersistence()
    }

    override func tearDown() {
        clearWorkspacePersistence()
        super.tearDown()
    }

    func testSyncActiveWorkspaceUsesContextFoldersForWorkspaceAndIndexInputs() {
        let store = WorkspaceStore()
        let contextId = UUID()
        let base = "/tmp/ctx-\(UUID().uuidString)"
        let context = ProjectContext(
            id: contextId,
            kind: .singleProject,
            name: "Project Context",
            folderPaths: ["\(base)/", "\(base)/./", "\(base)/Sources/.."],
            excludedPaths: ["\(base)/.build"],
            isPinned: false
        )

        store.syncActiveWorkspace(with: context)

        XCTAssertEqual(store.activeWorkspaceId, contextId)
        let expectedPath = canonicalPath(base)
        XCTAssertEqual(store.activeWorkspace?.folderPaths, [expectedPath])
        XCTAssertEqual(store.activeWorkspacePaths.map(\.path), [expectedPath])
        XCTAssertEqual(store.activeExcludedPaths, [canonicalPath("\(base)/.build")])
    }

    func testSyncActiveWorkspaceUpdatesExistingWorkspaceWhenContextChanges() {
        let store = WorkspaceStore()
        let contextId = UUID()
        let first = ProjectContext(
            id: contextId,
            kind: .singleProject,
            name: "Ctx",
            folderPaths: ["/tmp/a"],
            excludedPaths: [],
            isPinned: false
        )
        store.syncActiveWorkspace(with: first)

        let updated = ProjectContext(
            id: contextId,
            kind: .singleProject,
            name: "Ctx Updated",
            folderPaths: ["/tmp/b", "/tmp/c"],
            excludedPaths: ["/tmp/b/.build"],
            isPinned: false
        )
        store.syncActiveWorkspace(with: updated)

        XCTAssertEqual(store.activeWorkspaceId, contextId)
        XCTAssertEqual(store.activeWorkspace?.name, "Ctx Updated")
        XCTAssertEqual(store.activeWorkspace?.folderPaths, ["/tmp/b", "/tmp/c"])
        XCTAssertEqual(store.activeWorkspace?.excludedPaths, ["/tmp/b/.build"])
    }

    func testSyncActiveWorkspaceNormalizesFoldersAndExcludedPathsWithDuplicates() {
        let store = WorkspaceStore()
        let contextId = UUID()
        let home = NSHomeDirectory()
        let suffix = "tmp/context-\(UUID().uuidString)"
        let rawBase = "\(home)/\(suffix)"
        let canonicalBase = canonicalPath(rawBase)

        let initial = ProjectContext(
            id: contextId,
            kind: .singleProject,
            name: "Ctx",
            folderPaths: ["~/\(suffix)/", "~/\(suffix)/Sources/.."],
            excludedPaths: [],
            isPinned: false
        )

        let updated = ProjectContext(
            id: contextId,
            kind: .singleProject,
            name: "Ctx",
            folderPaths: ["\(rawBase)/", "\(rawBase)/Sources/.."],
            excludedPaths: ["\(rawBase)/.build/", "\(rawBase)/.build/../.build", "  "],
            isPinned: false
        )

        store.syncActiveWorkspace(with: initial)
        store.syncActiveWorkspace(with: updated)

        XCTAssertEqual(store.activeWorkspaceId, contextId)
        XCTAssertEqual(store.activeWorkspace?.folderPaths, [canonicalBase])
        XCTAssertEqual(store.activeWorkspace?.excludedPaths, [canonicalPath("\(rawBase)/.build")])
    }

    func testSyncActiveWorkspaceClearsActiveWorkspaceWhenContextIsNil() {
        let store = WorkspaceStore()
        let context = ProjectContext(
            kind: .singleProject,
            name: "Ctx",
            folderPaths: ["/tmp/a"],
            excludedPaths: [],
            isPinned: false
        )
        store.syncActiveWorkspace(with: context)
        XCTAssertNotNil(store.activeWorkspaceId)

        store.syncActiveWorkspace(with: nil)
        XCTAssertNil(store.activeWorkspaceId)
        XCTAssertTrue(store.activeWorkspacePaths.isEmpty)
    }

    private func canonicalPath(_ rawPath: String) -> String {
        URL(fileURLWithPath: rawPath).standardizedFileURL.path(percentEncoded: false)
    }

    private func clearWorkspacePersistence() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "CoderIDE.workspaces")
        defaults.removeObject(forKey: "CoderIDE.activeWorkspaceId")
        defaults.removeObject(forKey: "codebase_index_enabled")
    }
}
