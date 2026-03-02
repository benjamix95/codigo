import XCTest
@testable import CoderIDE

final class EventNormalizerLiveStateTests: XCTestCase {
    func testWebSearchStatusMapsToSearchingPhase() {
        let envelope = EventNormalizer.normalizeEnvelope(
            sourceProvider: "codex-cli",
            type: "web_search",
            payload: [
                "title": "Search",
                "query": "swiftui timeline",
                "status": "started",
                "queryId": "q1"
            ]
        )

        guard case .taskActivity(let activity)? = envelope.events.first else {
            XCTFail("Missing taskActivity event")
            return
        }
        XCTAssertEqual(activity.type, "web_search_started")
        XCTAssertEqual(activity.phase, .searching)
        XCTAssertTrue(activity.isRunning)
        XCTAssertEqual(activity.groupId, "q1")
    }

    func testProcessPausedMapsToPlanningAndStopped() {
        let envelope = EventNormalizer.normalizeEnvelope(
            sourceProvider: "codex-cli",
            type: "process_paused",
            payload: [:]
        )

        guard case .taskActivity(let activity)? = envelope.events.first else {
            XCTFail("Missing taskActivity event")
            return
        }
        XCTAssertEqual(activity.phase, .planning)
        XCTAssertFalse(activity.isRunning)
        XCTAssertEqual(activity.title, "Process paused")
        XCTAssertNil(activity.groupId)
    }

    func testTodoWriteNormalizesDashedStatus() {
        let events = EventNormalizer.normalize(
            type: "todo_write",
            payload: [
                "title": "Refactor parser",
                "status": "in-progress",
                "priority": "high"
            ]
        )

        guard case .todoWrite(let todo)? = events.first else {
            XCTFail("Missing todoWrite event")
            return
        }
        XCTAssertEqual(todo.status, .inProgress)
        XCTAssertEqual(todo.priority, .high)
    }

    func testTodoWriteAcceptsTaskAliasWhenTitleMissing() {
        let events = EventNormalizer.normalize(
            type: "todo_write",
            payload: [
                "task": "Align chat layout",
                "status": "pending",
                "priority": "medium"
            ]
        )

        guard case .todoWrite(let todo)? = events.first else {
            XCTFail("Missing todoWrite event")
            return
        }
        XCTAssertEqual(todo.title, "Align chat layout")
        XCTAssertEqual(todo.status, .pending)
    }

    func testTodoWriteAlsoEmitsTaskActivityForRealtimeVisibility() {
        let events = EventNormalizer.normalize(
            type: "todo_write",
            payload: [
                "title": "Fix stream reasoning",
                "status": "in_progress",
            ]
        )

        XCTAssertTrue(events.contains {
            if case .todoWrite = $0 { return true }
            return false
        })
        XCTAssertTrue(events.contains {
            if case .taskActivity(let activity) = $0 {
                return activity.type == "todo_write" && activity.title == "Todo updated"
            }
            return false
        })
    }

    func testTodoReadAlsoEmitsTaskActivityForRealtimeVisibility() {
        let events = EventNormalizer.normalize(
            type: "todo_read",
            payload: [:]
        )

        XCTAssertTrue(events.contains {
            if case .todoRead = $0 { return true }
            return false
        })
        XCTAssertTrue(events.contains {
            if case .taskActivity(let activity) = $0 { return activity.type == "todo_read" }
            return false
        })
    }

    func testPlanStepUpdateAlsoEmitsTaskActivityForRealtimeVisibility() {
        let events = EventNormalizer.normalize(
            type: "plan_step_update",
            payload: [
                "step_id": "1",
                "status": "running",
                "title": "Update parser"
            ]
        )

        XCTAssertTrue(events.contains {
            if case .planStepUpdate(let stepId, let status, let title) = $0 {
                return stepId == "1" && status == .running && title == "Update parser"
            }
            return false
        })
        XCTAssertTrue(events.contains {
            if case .taskActivity(let activity) = $0 {
                return activity.type == "plan_step_update"
                    && activity.title == "Update parser"
                    && activity.phase == .planning
                    && activity.isRunning
            }
            return false
        })
    }

    func testActivatePlanModeEmitsTypedEventAndTaskActivity() {
        let events = EventNormalizer.normalize(
            type: "activate_plan_mode",
            payload: [
                "reason": "User requested explicit planning phase"
            ]
        )

        XCTAssertTrue(events.contains {
            if case .activatePlanMode(let reason) = $0 {
                return reason == "User requested explicit planning phase"
            }
            return false
        })
        XCTAssertTrue(events.contains {
            if case .taskActivity(let activity) = $0 {
                return activity.type == "activate_plan_mode"
                    && activity.title == "Plan mode auto-activated"
                    && activity.phase == .planning
                    && !activity.isRunning
                    && activity.detail == "User requested explicit planning phase"
            }
            return false
        })
    }

    func testDebugPhaseUpdateEmitsTypedEventAndActivity() {
        let events = EventNormalizer.normalize(
            type: "debug_phase_update",
            payload: [
                "phase": "fixing",
                "detail": "Applying targeted patch"
            ]
        )

        XCTAssertTrue(events.contains {
            if case .debugPhaseUpdate(let phase, let detail) = $0 {
                return phase == .fixing && detail == "Applying targeted patch"
            }
            return false
        })
        XCTAssertTrue(events.contains {
            if case .taskActivity(let activity) = $0 {
                return activity.type == "debug_phase_update"
            }
            return false
        })
    }

    func testDebugUserRequestEmitsTypedEventAndActivity() {
        let events = EventNormalizer.normalize(
            type: "debug_user_request",
            payload: [
                "kind": "question",
                "prompt": "Mi confermi i passaggi per riprodurre?"
            ]
        )

        XCTAssertTrue(events.contains {
            if case .debugUserRequest(let kind, let prompt) = $0 {
                return kind == "question" && prompt.contains("riprodurre")
            }
            return false
        })
        XCTAssertTrue(events.contains {
            if case .taskActivity(let activity) = $0 {
                return activity.type == "debug_user_request"
            }
            return false
        })
    }

    func testLegacyDebugPanelEmitsValidationError() {
        let events = EventNormalizer.normalize(
            type: "debug_panel_update",
            payload: ["action": "open", "phase": "describing"]
        )

        guard case .taskActivity(let activity)? = events.first else {
            XCTFail("Missing taskActivity event")
            return
        }
        XCTAssertEqual(activity.type, "tool_validation_error")
        XCTAssertTrue(activity.title.contains("Legacy debug_panel"))
    }

    func testReasoningEventsAreIgnored() {
        let events = EventNormalizer.normalize(
            type: "reasoning",
            payload: [
                "title": "Reasoning",
                "detail": "Internal analysis"
            ]
        )

        XCTAssertTrue(events.isEmpty)
    }

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

    func testStrReplaceNormalizesToFileChangeEditingPhase() {
        let envelope = EventNormalizer.normalizeEnvelope(
            sourceProvider: "codex-cli",
            type: "str_replace",
            payload: [
                "title": "Edited Config.swift",
                "path": "Sources/CoderIDE/Config.swift",
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
                "command": "grep -n \"policy\" Sources/CoderIDE/ChatPanelView.swift",
                "cwd": "/Users/test/repo",
                "output": "Sources/CoderIDE/ChatPanelView.swift:10:policy"
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
                "command": "cat Sources/CoderIDE/ToolTraceVisibility.swift",
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

    func testDebugInstrumentEmitsTypedPayload() {
        let events = EventNormalizer.normalize(
            type: "debug_instrument",
            payload: [
                "path": "Sources/App.swift",
                "line": "73",
                "type": "timing",
                "expression": "compute()",
                "hypothesis_id": "abc123",
                "label": "hot path",
                "status": "completed"
            ]
        )

        XCTAssertTrue(events.contains {
            if case .debugInstrument(let payload) = $0 {
                return payload.filePath == "Sources/App.swift"
                    && payload.lineNumber == 73
                    && payload.type == "timing"
                    && payload.label == "hot path"
            }
            return false
        })
    }

    func testFakeMCPLikeEventDoesNotNormalizeAsMCP() {
        let events = EventNormalizer.normalize(
            type: "mcp_tool_call",
            payload: [
                "tool": "check_mcp_status",
                "detail": "Probe local status"
            ]
        )
        guard case .taskActivity(let activity)? = events.first else {
            XCTFail("Missing taskActivity event")
            return
        }
        XCTAssertEqual(activity.type, "command_execution")
        XCTAssertEqual(activity.title, "command_execution")
    }

    func testApplyPatchEnvelopeKindIsFileUpdate() {
        let envelope = EventNormalizer.normalizeEnvelope(
            sourceProvider: "codex-cli",
            type: "apply_patch",
            payload: ["path": "file.swift", "patch": "diff"]
        )
        XCTAssertEqual(envelope.kind, .fileUpdate)
    }

    func testWriteFileEnvelopeKindIsFileUpdate() {
        let envelope = EventNormalizer.normalizeEnvelope(
            sourceProvider: "codex-cli",
            type: "write_file",
            payload: ["path": "out.txt", "content": "data"]
        )
        XCTAssertEqual(envelope.kind, .fileUpdate)
    }

    func testNotebookEditEnvelopeKindIsFileUpdate() {
        let envelope = EventNormalizer.normalizeEnvelope(
            sourceProvider: "codex-cli",
            type: "notebook_edit",
            payload: ["path": "notebook.ipynb"]
        )
        XCTAssertEqual(envelope.kind, .fileUpdate)
    }

    func testNotebookWriteEnvelopeKindIsFileUpdate() {
        let envelope = EventNormalizer.normalizeEnvelope(
            sourceProvider: "codex-cli",
            type: "notebook_write",
            payload: ["path": "notebook.ipynb"]
        )
        XCTAssertEqual(envelope.kind, .fileUpdate)
    }
}
