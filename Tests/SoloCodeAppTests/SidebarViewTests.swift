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

        let hostingView = NSHostingView(rootView: view)
        XCTAssertNotNil(hostingView)
    }
}
