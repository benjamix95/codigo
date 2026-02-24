import XCTest
@testable import CoderEngine

final class CodexCLIProviderStreamParsingTests: XCTestCase {
    func testParseStreamJSONPayloadsRemovesControlPrefix() {
        let raw = "\u{04}\u{08}\u{08}{\"type\":\"turn.started\"}"
        let payloads = CodexCLIProvider.parseStreamJSONPayloads(from: raw)

        XCTAssertEqual(payloads.count, 1)
        XCTAssertEqual(payloads.first?["type"] as? String, "turn.started")
    }

    func testParseStreamJSONPayloadsExtractsJSONFromNoisyLine() {
        let raw = "2026-01-01T00:00:00Z WARN something {\"type\":\"turn.completed\"}"
        let payloads = CodexCLIProvider.parseStreamJSONPayloads(from: raw)

        XCTAssertEqual(payloads.count, 1)
        XCTAssertEqual(payloads.first?["type"] as? String, "turn.completed")
    }

    func testParseStreamJSONPayloadsHandlesConcatenatedObjects() {
        let raw = #"{"type":"turn.started"}{"type":"turn.completed"}"#
        let payloads = CodexCLIProvider.parseStreamJSONPayloads(from: raw)

        XCTAssertEqual(payloads.count, 2)
        XCTAssertEqual(payloads.first?["type"] as? String, "turn.started")
        XCTAssertEqual(payloads.last?["type"] as? String, "turn.completed")
    }

    func testReasoningAndAgentMessageRemainSeparated() {
        let events = runParser(events: [
            ["type": "turn.started"],
            [
                "type": "item.completed",
                "item": [
                    "id": "reasoning-1",
                    "type": "reasoning",
                    "text": "Sto valutando l'approccio migliore"
                ],
            ],
            [
                "type": "item.completed",
                "item": [
                    "id": "message-1",
                    "type": "agent_message",
                    "text": "Risposta finale pulita"
                ],
            ],
            ["type": "turn.completed"],
        ])

        let assistantText = events.compactMap { event -> String? in
            if case .textDelta(let text) = event { return text }
            return nil
        }.joined()

        let rawTurnEvents = events.compactMap { event -> String? in
            if case .raw(let type, _) = event, type == "turn_started" || type == "turn_completed" {
                return type
            }
            return nil
        }

        let rawReasoningEvents = events.compactMap { event -> String? in
            if case .raw(let type, _) = event, type == "reasoning" {
                return type
            }
            return nil
        }
        let reasoningPayloads = events.compactMap { event -> [String: String]? in
            if case .raw(let type, let payload) = event, type == "reasoning" {
                return payload
            }
            return nil
        }

        XCTAssertEqual(assistantText, "Risposta finale pulita")
        XCTAssertFalse(assistantText.contains("approccio migliore"))
        XCTAssertEqual(rawReasoningEvents.count, 1)
        XCTAssertEqual(reasoningPayloads.first?["title"], "Ragionamento")
        XCTAssertEqual(reasoningPayloads.first?["output"], "Sto valutando l'approccio migliore")
        XCTAssertEqual(reasoningPayloads.first?["group_id"], "reasoning-1")
        XCTAssertEqual(rawTurnEvents, ["turn_started", "turn_completed"])
    }

    func testReasoningUpdatesAreNotDedupedWhenOutputGrows() {
        let events = runParser(events: [
            ["type": "turn.started"],
            [
                "type": "item.updated",
                "item": [
                    "id": "reasoning-1",
                    "type": "reasoning",
                    "text": "Step 1"
                ],
            ],
            [
                "type": "item.updated",
                "item": [
                    "id": "reasoning-1",
                    "type": "reasoning",
                    "text": "Step 1\nStep 2"
                ],
            ],
            ["type": "turn.completed"],
        ])

        let reasoningPayloads = events.compactMap { event -> [String: String]? in
            if case .raw(let type, let payload) = event, type == "reasoning" {
                return payload
            }
            return nil
        }

        XCTAssertEqual(reasoningPayloads.count, 2)
        XCTAssertEqual(reasoningPayloads.first?["output"], "Step 1")
        XCTAssertEqual(reasoningPayloads.last?["output"], "Step 1\nStep 2")
    }

    func testCommandExecutionEmitsStartedAndCompletedStatuses() {
        let events = runParser(events: [
            ["type": "turn.started"],
            [
                "type": "item.started",
                "item": [
                    "id": "cmd-1",
                    "type": "command_execution",
                    "command": "ls -la"
                ],
            ],
            [
                "type": "item.completed",
                "item": [
                    "id": "cmd-1",
                    "type": "command_execution",
                    "command": "ls -la",
                    "output": "ok"
                ],
            ],
            ["type": "turn.completed"],
        ])

        let statuses = events.compactMap { event -> String? in
            if case .raw(let type, let payload) = event, type == "command_execution" {
                return payload["status"]
            }
            return nil
        }

        XCTAssertEqual(statuses, ["started", "completed"])
    }

    func testParserNormalizesEventTypesWithEmbeddedWhitespace() {
        let events = runParser(events: [
            ["type": "turn. started"],
            [
                "type": "item. started",
                "item": [
                    "id": "cmd-1",
                    "type": "command_execution",
                    "command": "ls -la"
                ],
            ],
            [
                "type": "item. completed",
                "item": [
                    "id": "cmd-1",
                    "type": "command_execution",
                    "command": "ls -la",
                    "output": "ok"
                ],
            ],
            ["type": "turn. completed"],
        ])

        let timelineTypes = events.compactMap { event -> String? in
            if case .raw(let type, _) = event { return type }
            return nil
        }

        XCTAssertTrue(timelineTypes.contains("turn_started"))
        XCTAssertTrue(timelineTypes.contains("turn_completed"))
        XCTAssertEqual(
            timelineTypes.filter { $0 == "command_execution" }.count,
            2
        )
    }

    func testTurnWithCompletedAgentMessageStillProducesFinalText() {
        let events = runParser(events: [
            ["type": "turn.started"],
            [
                "type": "item.completed",
                "item": [
                    "id": "message-final",
                    "type": "agent_message",
                    "text": "Output finale anche senza delta intermedi"
                ],
            ],
            ["type": "turn.completed"],
        ])

        let assistantDeltas = events.compactMap { event -> String? in
            if case .textDelta(let text) = event { return text }
            return nil
        }

        XCTAssertEqual(assistantDeltas, ["Output finale anche senza delta intermedi"])
    }

    private func runParser(events input: [[String: Any]]) -> [StreamEvent] {
        var state = CodexCLIProvider.CodexStreamParserState()
        var out: [StreamEvent] = []
        for json in input {
            out.append(contentsOf: CodexCLIProvider.parseStreamJSONEvent(json, state: &state))
        }
        out.append(contentsOf: CodexCLIProvider.finalizeStreamJSONState(state: &state))
        return out
    }
}
