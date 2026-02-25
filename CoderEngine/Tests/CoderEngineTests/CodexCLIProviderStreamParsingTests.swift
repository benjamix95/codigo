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
                    "text": "Final output even without intermediate deltas"
                ],
            ],
            ["type": "turn.completed"],
        ])

        let assistantDeltas = events.compactMap { event -> String? in
            if case .textDelta(let text) = event { return text }
            return nil
        }

        XCTAssertEqual(assistantDeltas, ["Final output even without intermediate deltas"])
    }

    func testDebugPanelMarkerEmitsDebugPanelUpdateRawEvent() {
        let events = runParser(events: [
            ["type": "turn.started"],
            [
                "type": "item.completed",
                "item": [
                    "id": "message-debug",
                    "type": "agent_message",
                    "text": "[CODERIDE:debug_panel|action=open|phase=analyzing]"
                ],
            ],
            ["type": "turn.completed"],
        ])

        let debugEvents = events.compactMap { event -> [String: String]? in
            if case .raw(let type, let payload) = event, type == "debug_panel_update" {
                return payload
            }
            return nil
        }

        XCTAssertEqual(debugEvents.count, 1)
        XCTAssertEqual(debugEvents.first?["action"], "open")
        XCTAssertEqual(debugEvents.first?["phase"], "analyzing")
    }

    func testRawDedupKeyDiffersWhenPayloadChangesWithSameIdentifierAndStatus() {
        let base: [String: String] = [
            "id": "cmd-1",
            "status": "started",
            "output": "line-1"
        ]
        let changed: [String: String] = [
            "id": "cmd-1",
            "status": "started",
            "output": "line-2"
        ]

        let key1 = CodexCLIProvider.rawDedupKey(type: "command_execution", payload: base)
        let key2 = CodexCLIProvider.rawDedupKey(type: "command_execution", payload: changed)
        XCTAssertNotEqual(key1, key2)
    }

    func testRawDedupKeyRemainsStableForIdenticalPayload() {
        let payload: [String: String] = [
            "id": "cmd-1",
            "status": "completed",
            "output": "ok"
        ]
        let key1 = CodexCLIProvider.rawDedupKey(type: "command_execution", payload: payload)
        let key2 = CodexCLIProvider.rawDedupKey(type: "command_execution", payload: payload)
        XCTAssertEqual(key1, key2)
    }

    func testFileChangeParsesNestedPathCountersAndDiffPreview() {
        let json: [String: Any] = [
            "type": "item.completed",
            "item": [
                "id": "fc-1",
                "type": "file_change",
                "change_type": "create",
                "metadata": [
                    "target_path": "Tests/CoderIDETests/FontPreferencesTests.swift",
                    "stats": [
                        "insertions": 28,
                        "deletions_count": 0,
                    ],
                ],
                "patch": "@@ -0,0 +1 @@\n+import XCTest",
            ],
        ]

        guard let parsed = CodexCLIProvider.parseRawEvent(from: json) else {
            XCTFail("Expected file_change raw event")
            return
        }

        XCTAssertEqual(parsed.type, "file_change")
        XCTAssertEqual(parsed.payload["title"], "Created FontPreferencesTests.swift")
        XCTAssertEqual(parsed.payload["path"], "Tests/CoderIDETests/FontPreferencesTests.swift")
        XCTAssertEqual(parsed.payload["linesAdded"], "28")
        XCTAssertEqual(parsed.payload["linesRemoved"], "0")
        XCTAssertEqual(parsed.payload["change_type"], "create")
        XCTAssertEqual(parsed.payload["diffPreview"], "@@ -0,0 +1 @@\n+import XCTest")
    }

    func testFileChangeFallbackTitleWhenPathMissing() {
        let json: [String: Any] = [
            "type": "item.completed",
            "item": [
                "id": "fc-2",
                "type": "file_change",
            ],
        ]

        guard let parsed = CodexCLIProvider.parseRawEvent(from: json) else {
            XCTFail("Expected file_change raw event")
            return
        }

        XCTAssertEqual(parsed.payload["title"], "Edited file")
        XCTAssertEqual(parsed.payload["detail"], "")
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
