import XCTest
import AppKit
import SwiftUI
@testable import CoderIDE
@testable import CoderEngine

@MainActor
final class SidebarViewTests: XCTestCase {
    func testSidebarViewBuildsWithContextAndConversation() {
        let providerRegistry = ProviderRegistry()
        let chatStore = ChatStore(userDefaults: UserDefaults(suiteName: #filePath) ?? .standard)
        let workspaceStore = WorkspaceStore()
        let projectContextStore = ProjectContextStore()

        let context = ProjectContext(
            kind: .singleProject,
            name: "Workspace",
            folderPaths: ["/tmp/workspace"],
            isPinned: true
        )
        projectContextStore.upsert(context)
        projectContextStore.activeContextId = context.id

        let conversationId = chatStore.createConversation(
            contextId: context.id,
            contextFolderPath: nil
        )

        var selectedConversationId: UUID? = conversationId
        let todoStore = TodoStore(
            storageKey: "SidebarViewTests.todos",
            userDefaults: UserDefaults(suiteName: #filePath + ".todos") ?? .standard
        )
        let view = SidebarView(
            selectedConversationId: Binding(
                get: { selectedConversationId },
                set: { selectedConversationId = $0 }
            ),
            showSettings: .constant(false),
            isSelectingProjectFolders: .constant(false),
            preferActiveContextForGlobalThread: true
        )
        .environmentObject(providerRegistry)
        .environmentObject(chatStore)
        .environmentObject(workspaceStore)
        .environmentObject(projectContextStore)
        .environmentObject(todoStore)
        .environmentObject(ToolTraceStore())
        .environmentObject(PipelineIntegrationService())

        let hostingView = NSHostingView(rootView: view)
        XCTAssertNotNil(hostingView)
    }

    func testThreadCreationContextValidationAcceptsRealDirectory() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let context = ProjectContext(
            kind: .singleProject,
            name: "Project",
            folderPaths: [root.path],
            isPinned: true
        )

        XCTAssertTrue(isValidThreadCreationContext(context))
    }

    func testThreadCreationContextValidationRejectsEmptyWorkspacePlaceholder() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let workspacePlaceholder = parent.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspacePlaceholder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: parent) }

        let context = ProjectContext(
            kind: .workspace,
            name: "Workspace",
            folderPaths: [workspacePlaceholder.path],
            isPinned: true
        )

        XCTAssertFalse(isValidThreadCreationContext(context))
    }
}
