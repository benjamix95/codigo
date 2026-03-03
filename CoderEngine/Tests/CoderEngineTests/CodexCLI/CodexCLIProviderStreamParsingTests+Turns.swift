import Foundation
import XCTest
@testable import CoderEngine

extension CodexCLIProviderStreamParsingTests {
    // MARK: - Multi-Turn Intermediate Text → Reasoning

    func testMultiTurnMovesIntermediateTextToReasoning() {
        let events = runParser(events: [
            ["type": "turn.started"],
            [
                "type": "item.completed",
                "item": [
                    "type": "agent_message",
                    "text": "Let me check the file.",
                ],
            ],
            ["type": "turn.completed"],
            ["type": "turn.started"],
            [
                "type": "item.completed",
                "item": [
                    "type": "agent_message",
                    "text": "Done! Here is the result.",
                ],
            ],
            ["type": "turn.completed"],
        ])

        let visibleDeltas = events.compactMap { event -> String? in
            if case .textDelta(let text) = event { return text }
            return nil
        }

        let replaces = events.compactMap { event -> String? in
            if case .textReplace(let text) = event { return text }
            return nil
        }

        let reasoningPayloads = events.compactMap { event -> [String: String]? in
            if case .raw(let type, let payload) = event, type == "reasoning" {
                return payload
            }
            return nil
        }

        XCTAssertTrue(visibleDeltas.contains("Let me check the file."))
        XCTAssertTrue(visibleDeltas.contains("Done! Here is the result."))

        XCTAssertEqual(replaces.count, 1)
        XCTAssertEqual(replaces.first, "")

        let intermediateReasoning = reasoningPayloads.filter { $0["group_id"] == "codex-intermediate-turns" }
        XCTAssertEqual(intermediateReasoning.count, 1)
        XCTAssertTrue(intermediateReasoning.first?["output"]?.contains("Let me check the file.") == true)
    }

    func testSingleTurnDoesNotEmitTextReplace() {
        let events = runParser(events: [
            ["type": "turn.started"],
            [
                "type": "item.completed",
                "item": [
                    "type": "agent_message",
                    "text": "Single turn answer.",
                ],
            ],
            ["type": "turn.completed"],
        ])

        let replaces = events.compactMap { event -> String? in
            if case .textReplace(let text) = event { return text }
            return nil
        }

        let visibleText = events.compactMap { event -> String? in
            if case .textDelta(let text) = event { return text }
            return nil
        }.joined()

        XCTAssertEqual(replaces.count, 0, "Single turn should not emit textReplace")
        XCTAssertEqual(visibleText, "Single turn answer.")
    }

    func testThreeTurnKeepsOnlyLastTurnVisible() {
        let events = runParser(events: [
            ["type": "turn.started"],
            [
                "type": "item.completed",
                "item": ["type": "agent_message", "text": "Turn 1 text."],
            ],
            ["type": "turn.completed"],
            ["type": "turn.started"],
            [
                "type": "item.completed",
                "item": ["type": "agent_message", "text": "Turn 2 text."],
            ],
            ["type": "turn.completed"],
            ["type": "turn.started"],
            [
                "type": "item.completed",
                "item": ["type": "agent_message", "text": "Final answer."],
            ],
            ["type": "turn.completed"],
        ])

        let replaces = events.compactMap { event -> String? in
            if case .textReplace(let text) = event { return text }
            return nil
        }

        let intermediateReasoning = events.compactMap { event -> [String: String]? in
            if case .raw(let type, let payload) = event,
               type == "reasoning",
               payload["group_id"] == "codex-intermediate-turns" {
                return payload
            }
            return nil
        }

        XCTAssertEqual(replaces.count, 2, "Two turn transitions should emit two textReplace events")
        XCTAssertEqual(intermediateReasoning.count, 2, "Two intermediate turns should emit two reasoning events")
        XCTAssertTrue(intermediateReasoning[0]["output"]?.contains("Turn 1") == true)
        XCTAssertTrue(intermediateReasoning[1]["output"]?.contains("Turn 2") == true)
    }
}
