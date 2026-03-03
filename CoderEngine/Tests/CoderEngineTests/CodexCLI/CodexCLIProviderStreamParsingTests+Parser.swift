import Foundation
import XCTest
@testable import CoderEngine

extension CodexCLIProviderStreamParsingTests {
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
                    "text": "Evaluating the best approach"
                ],
            ],
            [
                "type": "item.completed",
                "item": [
                    "id": "message-1",
                    "type": "agent_message",
                    "text": "Clean final answer"
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

        XCTAssertEqual(assistantText, "Clean final answer")
        XCTAssertFalse(assistantText.contains("best approach"))
        XCTAssertEqual(rawReasoningEvents.count, 1)
        XCTAssertEqual(reasoningPayloads.first?["title"], "Reasoning")
        XCTAssertEqual(reasoningPayloads.first?["output"], "Evaluating the best approach")
        XCTAssertEqual(reasoningPayloads.first?["group_id"], "reasoning-1")
        XCTAssertEqual(rawTurnEvents, ["turn_started", "turn_completed"])
    }

    func testReasoningUsesSwarmGroupIdWhenSwarmIdPresent() {
        let events = runParser(events: [
            [
                "type": "item.completed",
                "item": [
                    "id": "reasoning-legacy-1",
                    "type": "reasoning",
                    "swarm_id": "s-arch",
                    "text": "Coalescing stream updates for stable grouping"
                ],
            ],
        ])

        let reasoningPayloads = events.compactMap { event -> [String: String]? in
            if case .raw(let type, let payload) = event, type == "reasoning" {
                return payload
            }
            return nil
        }

        XCTAssertEqual(reasoningPayloads.count, 1)
        XCTAssertEqual(reasoningPayloads.first?["swarm_id"], "s-arch")
        XCTAssertEqual(reasoningPayloads.first?["group_id"], "swarm-s-arch")
    }

    func testReasoningTrimmedSwarmIdGetsCanonicalGroupId() {
        let events = runParser(events: [
            [
                "type": "item.completed",
                "item": [
                    "id": "reasoning-legacy-2",
                    "type": "reasoning",
                    "swarm_id": "  s-ops  ",
                    "text": "Trimming is expected before group assignment"
                ],
            ],
        ])

        let reasoningPayloads = events.compactMap { event -> [String: String]? in
            if case .raw(let type, let payload) = event, type == "reasoning" {
                return payload
            }
            return nil
        }

        XCTAssertEqual(reasoningPayloads.count, 1)
        XCTAssertEqual(reasoningPayloads.first?["swarm_id"], "s-ops")
        XCTAssertEqual(reasoningPayloads.first?["group_id"], "swarm-s-ops")
    }

    func testReasoningSkipsDoubleSwarmPrefixInGroupId() {
        let events = runParser(events: [
            [
                "type": "item.completed",
                "item": [
                    "id": "reasoning-legacy-3",
                    "type": "reasoning",
                    "swarm_id": "swarm-s-prefixed",
                    "text": "Prefixed swarm IDs should remain single-prefixed"
                ],
            ],
        ])

        let reasoningPayloads = events.compactMap { event -> [String: String]? in
            if case .raw(let type, let payload) = event, type == "reasoning" {
                return payload
            }
            return nil
        }

        XCTAssertEqual(reasoningPayloads.count, 1)
        XCTAssertEqual(reasoningPayloads.first?["swarm_id"], "swarm-s-prefixed")
        XCTAssertEqual(reasoningPayloads.first?["group_id"], "swarm-s-prefixed")
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
}
