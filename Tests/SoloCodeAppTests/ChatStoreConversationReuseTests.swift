import XCTest
@testable import CoderIDE

@MainActor
final class ChatStoreConversationReuseTests: XCTestCase {
    func testReusableEmptyConversationRequiresMatchingMode() throws {
        let suiteName = "ChatStoreConversationReuseTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = ChatStore(userDefaults: defaults)
        let contextId = UUID()
        let planConversationId = store.createConversation(
            contextId: contextId,
            contextFolderPath: "/tmp/project",
            mode: .plan
        )

        XCTAssertNil(
            store.reusableEmptyConversation(
                contextId: contextId,
                contextFolderPath: "/tmp/project",
                mode: nil
            )
        )

        XCTAssertEqual(
            store.reusableEmptyConversation(
                contextId: contextId,
                contextFolderPath: "/tmp/project",
                mode: .plan
            )?.id,
            planConversationId
        )
    }
}
