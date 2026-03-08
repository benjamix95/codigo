import XCTest
@testable import CoderIDE

final class TerminalAddToChatTests: XCTestCase {
    func testTerminalAddToChatNotificationNameExists() {
        XCTAssertEqual(
            Notification.Name.terminalAddToChat.rawValue,
            "CoderIDE.TerminalAddToChat"
        )
    }

    func testTerminalAddToChatNotificationCarriesContent() {
        let expectation = expectation(description: "Notification received")
        var receivedContent: String?

        let observer = NotificationCenter.default.addObserver(
            forName: .terminalAddToChat,
            object: nil,
            queue: .main
        ) { notification in
            receivedContent = notification.userInfo?["content"] as? String
            expectation.fulfill()
        }

        NotificationCenter.default.post(
            name: .terminalAddToChat,
            object: nil,
            userInfo: ["content": "test terminal output"]
        )

        waitForExpectations(timeout: 2)
        XCTAssertEqual(receivedContent, "test terminal output")
        NotificationCenter.default.removeObserver(observer)
    }

    func testTerminalAddToChatNotificationWithEmptyContent() {
        let expectation = expectation(description: "Notification received")
        var receivedContent: String?

        let observer = NotificationCenter.default.addObserver(
            forName: .terminalAddToChat,
            object: nil,
            queue: .main
        ) { notification in
            receivedContent = notification.userInfo?["content"] as? String
            expectation.fulfill()
        }

        NotificationCenter.default.post(
            name: .terminalAddToChat,
            object: nil,
            userInfo: ["content": ""]
        )

        waitForExpectations(timeout: 2)
        XCTAssertEqual(receivedContent, "")
        NotificationCenter.default.removeObserver(observer)
    }
}
