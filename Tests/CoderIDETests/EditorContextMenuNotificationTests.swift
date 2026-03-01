import XCTest
@testable import CoderIDE

final class EditorContextMenuNotificationTests: XCTestCase {
    func testEditorFixInChatNotificationNameExists() {
        XCTAssertEqual(
            Notification.Name.editorFixInChat.rawValue,
            "CoderIDE.EditorFixInChat"
        )
    }

    func testEditorAddToChatNotificationNameExists() {
        XCTAssertEqual(
            Notification.Name.editorAddToChat.rawValue,
            "CoderIDE.EditorAddToChat"
        )
    }

    func testFixInChatNotificationCarriesPromptAndPath() {
        let expectation = expectation(description: "Fix in chat received")
        var receivedPrompt: String?
        var receivedPath: String?

        let observer = NotificationCenter.default.addObserver(
            forName: .editorFixInChat,
            object: nil,
            queue: .main
        ) { notification in
            receivedPrompt = notification.userInfo?["prompt"] as? String
            receivedPath = notification.userInfo?["path"] as? String
            expectation.fulfill()
        }

        NotificationCenter.default.post(
            name: .editorFixInChat,
            object: nil,
            userInfo: [
                "prompt": "Fix this code from `test.swift` (line 10):\n```\nlet x = 1\n```",
                "path": "/path/to/test.swift"
            ]
        )

        waitForExpectations(timeout: 2)
        XCTAssertNotNil(receivedPrompt)
        XCTAssertTrue(receivedPrompt?.contains("Fix this code") == true)
        XCTAssertEqual(receivedPath, "/path/to/test.swift")
        NotificationCenter.default.removeObserver(observer)
    }

    func testAddToChatNotificationCarriesContentAndPath() {
        let expectation = expectation(description: "Add to chat received")
        var receivedContent: String?
        var receivedPath: String?

        let observer = NotificationCenter.default.addObserver(
            forName: .editorAddToChat,
            object: nil,
            queue: .main
        ) { notification in
            receivedContent = notification.userInfo?["content"] as? String
            receivedPath = notification.userInfo?["path"] as? String
            expectation.fulfill()
        }

        NotificationCenter.default.post(
            name: .editorAddToChat,
            object: nil,
            userInfo: [
                "content": "From `main.swift` (line 5):\n```\nprint(42)\n```",
                "path": "/path/to/main.swift"
            ]
        )

        waitForExpectations(timeout: 2)
        XCTAssertNotNil(receivedContent)
        XCTAssertTrue(receivedContent?.contains("main.swift") == true)
        XCTAssertEqual(receivedPath, "/path/to/main.swift")
        NotificationCenter.default.removeObserver(observer)
    }
}
