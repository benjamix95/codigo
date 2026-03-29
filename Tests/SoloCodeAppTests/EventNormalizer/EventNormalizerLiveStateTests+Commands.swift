import XCTest
@testable import CoderIDE

extension EventNormalizerLiveStateTests {
    func testTurnStartedMapsToPlanningRunning() {
        let envelope = EventNormalizer.normalizeEnvelope(
            sourceProvider: "codex-cli",
            type: "turn_started",
            payload: [
                "title": "Turn started",
                "status": "started",
                "group_id": "turn-1"
            ]
        )

        guard case .taskActivity(let activity)? = envelope.events.first else {
            XCTFail("Missing taskActivity event")
            return
        }
        XCTAssertEqual(activity.type, "turn_started")
        XCTAssertEqual(activity.phase, .planning)
        XCTAssertTrue(activity.isRunning)
        XCTAssertEqual(activity.groupId, "turn-1")
    }

    func testTurnCompletedMapsToPlanningStopped() {
        let envelope = EventNormalizer.normalizeEnvelope(
            sourceProvider: "codex-cli",
            type: "turn_completed",
            payload: [
                "title": "Turn completed",
                "status": "completed",
                "group_id": "turn-1"
            ]
        )

        guard case .taskActivity(let activity)? = envelope.events.first else {
            XCTFail("Missing taskActivity event")
            return
        }
        XCTAssertEqual(activity.type, "turn_completed")
        XCTAssertEqual(activity.phase, .planning)
        XCTAssertFalse(activity.isRunning)
        XCTAssertEqual(activity.groupId, "turn-1")
    }

    func testReadBatchCompletedSemanticSearchMapsToSemanticType() {
        let envelope = EventNormalizer.normalizeEnvelope(
            sourceProvider: "codex-cli",
            type: "read_batch_completed",
            payload: [
                "tool": "semantic_search",
                "status": "completed",
                "query": "authentication flow"
            ]
        )

        guard case .taskActivity(let activity)? = envelope.events.first else {
            XCTFail("Missing taskActivity event")
            return
        }
        XCTAssertEqual(activity.type, "semantic_search")
        XCTAssertEqual(activity.phase, .searching)
        XCTAssertFalse(activity.isRunning)
    }

    func testReadBatchCompletedNamespacedSemanticSearchMapsToSemanticType() {
        let envelope = EventNormalizer.normalizeEnvelope(
            sourceProvider: "codex-cli",
            type: "read_batch_completed",
            payload: [
                "tool": "functions.semantic_search",
                "status": "completed",
                "query": "trace activity"
            ]
        )

        guard case .taskActivity(let activity)? = envelope.events.first else {
            XCTFail("Missing taskActivity event")
            return
        }
        XCTAssertEqual(activity.type, "semantic_search")
        XCTAssertEqual(activity.phase, .searching)
        XCTAssertFalse(activity.isRunning)
    }

    func testReadBatchCompletedNamespacedCoderideSemanticSearchPreservesMCPMarkers() {
        let envelope = EventNormalizer.normalizeEnvelope(
            sourceProvider: "codex-cli",
            type: "read_batch_completed",
            payload: [
                "tool": "semantic_search",
                "mcp_tool": "coderide_semantic_search",
                "is_mcp": "true",
                "status": "completed",
                "query": "trace activity"
            ]
        )

        guard case .taskActivity(let activity)? = envelope.events.first else {
            XCTFail("Missing taskActivity event")
            return
        }
        XCTAssertEqual(activity.type, "semantic_search")
        XCTAssertEqual(activity.phase, .searching)
        XCTAssertFalse(activity.isRunning)
        XCTAssertEqual(activity.payload["is_mcp"], "true")
        XCTAssertEqual(activity.payload["mcp_tool"], "coderide_semantic_search")
    }

    func testStrReplaceNormalizesToFileChangeEditingPhase() {
        let envelope = EventNormalizer.normalizeEnvelope(
            sourceProvider: "codex-cli",
            type: "str_replace",
            payload: [
                "title": "Edited Config.swift",
                "path": "App/SoloCodeApp/Sources/Config.swift",
                "tool": "str_replace",
            ]
        )

        XCTAssertEqual(envelope.kind, .fileUpdate)
        guard case .taskActivity(let activity)? = envelope.events.first else {
            XCTFail("Missing taskActivity event")
            return
        }
        XCTAssertEqual(activity.type, "file_change")
        XCTAssertEqual(activity.phase, .editing)
    }

    func testCommandExecutionGrepEmitsInstantGrep() {
        let events = EventNormalizer.normalize(
            type: "command_execution",
            payload: [
                "command": "grep -n \"policy\" App/SoloCodeApp/Sources/ChatPanelView.swift",
                "cwd": "/Users/test/repo",
                "output": "App/SoloCodeApp/Sources/ChatPanelView.swift:10:policy"
            ]
        )

        XCTAssertTrue(events.contains {
            if case .instantGrep = $0 { return true }
            return false
        })
    }

    func testCommandExecutionCatEmitsSyntheticReadActivity() {
        let events = EventNormalizer.normalize(
            type: "command_execution",
            payload: [
                "command": "cat App/SoloCodeApp/Sources/ToolTraceVisibility.swift",
            ]
        )

        XCTAssertTrue(events.contains {
            if case .taskActivity(let activity) = $0 {
                return activity.type == "read_batch_completed"
                    && activity.payload["source"] == "synthetic_command_read"
            }
            return false
        })
    }

    func testDebugLogEmitsTypedAndTaskActivityEvents() {
        let events = EventNormalizer.normalize(
            type: "debug_log",
            payload: [
                "severity": "error",
                "source": "NetworkManager.swift:42",
                "message": "Connection refused",
                "category": "runtime",
                "status": "completed"
            ]
        )

        XCTAssertTrue(events.contains {
            if case .debugLog(let payload) = $0 {
                return payload.severity == .error
                    && payload.source == "NetworkManager.swift:42"
                    && payload.message == "Connection refused"
            }
            return false
        })

        XCTAssertTrue(events.contains {
            if case .taskActivity(let activity) = $0 {
                return activity.type == "debug_log"
                    && activity.phase == .executing
                    && !activity.isRunning
            }
            return false
        })
    }

    func testDebugMarkEmitsTypedPayload() {
        let events = EventNormalizer.normalize(
            type: "debug_mark",
            payload: [
                "marker_info": "Sources/App.swift|42|added print",
                "status": "completed"
            ]
        )

        XCTAssertTrue(events.contains {
            if case .debugMark(let payload) = $0 {
                return payload.filePath == "Sources/App.swift"
                    && payload.lineNumber == 42
                    && payload.comment == "added print"
            }
            return false
        })
    }

    func testDebugMarkParsesFourPartMarkerInfoWithoutLeakingTypeIntoComment() {
        let events = EventNormalizer.normalize(
            type: "debug_mark",
            payload: [
                "marker_info": "Sources/App.swift|42|added print|log",
                "status": "completed"
            ]
        )

        XCTAssertTrue(events.contains {
            if case .debugMark(let payload) = $0 {
                return payload.filePath == "Sources/App.swift"
                    && payload.lineNumber == 42
                    && payload.comment == "added print"
            }
            return false
        })
    }

    func testDebugCleanDryRunEmitsTypedPayload() {
        let events = EventNormalizer.normalize(
            type: "debug_clean",
            payload: [
                "dry_run": "true",
                "detail": "Preview only",
                "status": "preview"
            ]
        )

        XCTAssertTrue(events.contains {
            if case .debugClean(let payload) = $0 {
                return payload.dryRun
                    && payload.status == "preview"
                    && payload.detail == "Preview only"
            }
            return false
        })
    }

    func testDebugCleanDryRunAcceptsNumericAlias() {
        let events = EventNormalizer.normalize(
            type: "debug_clean",
            payload: [
                "dry_run": "1",
                "status": "preview"
            ]
        )

        XCTAssertTrue(events.contains {
            if case .debugClean(let payload) = $0 {
                return payload.dryRun
            }
            return false
        })
    }

    func testDebugHypothesizeParsesIDBasedPayload() {
        let id = UUID()
        let events = EventNormalizer.normalize(
            type: "debug_hypothesize",
            payload: [
                "action": "update",
                "hypothesis_id": id.uuidString,
                "hypothesis_status": "confirmed",
                "evidence": "Reproduced with runtime logs"
            ]
        )

        XCTAssertTrue(events.contains {
            if case .debugHypothesize(let payload) = $0 {
                return payload.action == "update"
                    && payload.hypothesisId == id
                    && payload.status == .confirmed
            }
            return false
        })
    }
}
