import XCTest
@testable import CoderIDE

final class ChatTimelineBlockIdentitySanitizerTests: XCTestCase {
    func testSanitizerLeavesUniqueBlockIDsUntouched() {
        let blocks = [
            makeBlock(id: "primary-text", kind: .primaryText, sequence: 0),
            makeBlock(id: "reasoning", kind: .reasoning, sequence: 1),
        ]

        let sanitized = sanitizeTimelineBlockIDs(blocks)

        XCTAssertEqual(sanitized.map(\.id), ["primary-text", "reasoning"])
    }

    func testSanitizerMakesDuplicateReasoningIDsUniqueWhilePreservingOrder() {
        let blocks = [
            makeBlock(id: "reasoning", kind: .reasoning, sequence: 0, text: "First"),
            makeBlock(id: "reasoning", kind: .reasoning, sequence: 2, text: "Second"),
            makeBlock(id: "reasoning", kind: .reasoning, sequence: 4, text: "Third"),
        ]

        let sanitized = sanitizeTimelineBlockIDs(blocks)

        XCTAssertEqual(
            sanitized.map(\.id),
            ["reasoning", "reasoning__dup1-seq2", "reasoning__dup2-seq4"]
        )
        XCTAssertEqual(sanitized.map(\.sequence), [0, 2, 4])
        XCTAssertEqual(sanitized.map(\.text), ["First", "Second", "Third"])
    }

    func testSanitizerHandlesMixedDuplicateIDsIndependently() {
        let blocks = [
            makeBlock(id: "reasoning", kind: .reasoning, sequence: 0),
            makeBlock(id: "primary-text", kind: .primaryText, sequence: 1),
            makeBlock(id: "reasoning", kind: .reasoning, sequence: 2),
            makeBlock(id: "primary-text", kind: .primaryText, sequence: 3),
        ]

        let sanitized = sanitizeTimelineBlockIDs(blocks)

        XCTAssertEqual(
            sanitized.map(\.id),
            ["reasoning", "primary-text", "reasoning__dup1-seq2", "primary-text__dup1-seq3"]
        )
    }

    private func makeBlock(
        id: String,
        kind: ChatTimelineBlockKind,
        sequence: Int,
        text: String = "text"
    ) -> PersistedChatTimelineBlock {
        PersistedChatTimelineBlock(
            id: id,
            kind: kind,
            text: text,
            sequence: sequence
        )
    }
}
