import XCTest
@testable import CoderIDE

@MainActor
final class WorktreeContextRouterTests: XCTestCase {
    private var tempDirURL: URL!
    private var chatDefaults: UserDefaults!
    private var chatSuiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("worktree-router-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirURL, withIntermediateDirectories: true)

        chatSuiteName = "worktree-router-chat-\(UUID().uuidString)"
        chatDefaults = UserDefaults(suiteName: chatSuiteName)
        chatDefaults.removePersistentDomain(forName: chatSuiteName)

        clearContextPersistence()
    }

    override func tearDownWithError() throws {
        if let tempDirURL {
            try? FileManager.default.removeItem(at: tempDirURL)
        }
        if let chatSuiteName {
            chatDefaults?.removePersistentDomain(forName: chatSuiteName)
        }
        clearContextPersistence()
        tempDirURL = nil
        chatDefaults = nil
        chatSuiteName = nil
        try super.tearDownWithError()
    }

    func testSwitchConversationCreatesProjectContextAndAssignsConversation() throws {
        let chatStore = ChatStore(userDefaults: chatDefaults)
        let conversationId = chatStore.createConversation(contextId: nil, contextFolderPath: nil, mode: nil)
        let projectContextStore = ProjectContextStore()
        let workspaceStore = WorkspaceStore()

        try initializeGitRepository(at: tempDirURL)

        try WorktreeContextRouter.switchConversation(
            conversationId: conversationId,
            toProjectPath: tempDirURL.path,
            chatStore: chatStore,
            projectContextStore: projectContextStore,
            workspaceStore: workspaceStore
        )

        let conv = try XCTUnwrap(chatStore.conversation(for: conversationId))
        let contextId = try XCTUnwrap(conv.contextId)
        let context = try XCTUnwrap(projectContextStore.context(id: contextId))
        XCTAssertEqual(context.folderPaths, [tempDirURL.path])
        XCTAssertEqual(projectContextStore.activeContextId, contextId)
        XCTAssertEqual(workspaceStore.activeWorkspaceId, contextId)
        XCTAssertEqual(workspaceStore.workspaces.first(where: { $0.id == contextId })?.folderPaths, [tempDirURL.path])
    }

    func testSwitchConversationRejectsMissingDirectory() {
        let chatStore = ChatStore(userDefaults: chatDefaults)
        let conversationId = chatStore.createConversation(contextId: nil, contextFolderPath: nil, mode: nil)

        XCTAssertThrowsError(
            try WorktreeContextRouter.switchConversation(
                conversationId: conversationId,
                toProjectPath: tempDirURL.appendingPathComponent("missing").path,
                chatStore: chatStore,
                projectContextStore: ProjectContextStore(),
                workspaceStore: WorkspaceStore()
            )
        )
    }

    func testSwitchConversationRejectsNonGitDirectory() throws {
        let plainDirectory = tempDirURL.appendingPathComponent("plain")
        try FileManager.default.createDirectory(at: plainDirectory, withIntermediateDirectories: true)

        let chatStore = ChatStore(userDefaults: chatDefaults)
        let conversationId = chatStore.createConversation(contextId: nil, contextFolderPath: nil, mode: nil)

        XCTAssertThrowsError(
            try WorktreeContextRouter.switchConversation(
                conversationId: conversationId,
                toProjectPath: plainDirectory.path,
                chatStore: chatStore,
                projectContextStore: ProjectContextStore(),
                workspaceStore: WorkspaceStore()
            )
        )
    }

    private func clearContextPersistence() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "CoderIDE.projectContexts")
        defaults.removeObject(forKey: "CoderIDE.activeContextId")
        defaults.removeObject(forKey: "CoderIDE.lastActiveConversationByContext")
        defaults.removeObject(forKey: "CoderIDE.workspaces")
        defaults.removeObject(forKey: "CoderIDE.activeWorkspaceId")
    }

    private func initializeGitRepository(at url: URL) throws {
        try runGit(["init"], cwd: url.path)
        try runGit(["config", "user.email", "test@example.com"], cwd: url.path)
        try runGit(["config", "user.name", "Git Test"], cwd: url.path)
        try "hello".write(
            to: url.appendingPathComponent("a.txt"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "."], cwd: url.path)
        try runGit(["commit", "-m", "init"], cwd: url.path)
    }

    private func runGit(_ args: [String], cwd: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = args
        process.currentDirectoryURL = URL(fileURLWithPath: cwd)
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let stdout = String(
                data: out.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            let stderr = String(
                data: err.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            throw NSError(
                domain: "WorktreeContextRouterTests",
                code: Int(process.terminationStatus),
                userInfo: [
                    NSLocalizedDescriptionKey: "git failed\nstdout: \(stdout)\nstderr: \(stderr)"
                ]
            )
        }
    }
}
