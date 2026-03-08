import XCTest
@testable import CoderIDE

extension EventNormalizerLiveStateTests {
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

    func testPlanLifecycleEventsAreClassifiedAsPlanningActivities() {
        let envelope = EventNormalizer.normalizeEnvelope(
            sourceProvider: "codex-cli",
            type: "plan_step_batch_update",
            payload: [
                "updates": #"[{"step_id":"1","status":"running"}]"#
            ]
        )

        XCTAssertEqual(envelope.kind, .planLifecycle)
        XCTAssertTrue(envelope.events.contains {
            if case .taskActivity(let activity) = $0 {
                return activity.type == "plan_step_batch_update"
                    && activity.phase == .planning
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

    func testDebugSetPhaseAliasMapsToDebugPhaseUpdate() {
        let envelope = EventNormalizer.normalizeEnvelope(
            sourceProvider: "test",
            type: "debug_set_phase",
            payload: [
                "phase": "verifying",
                "detail": "Running focused checks"
            ]
        )

        XCTAssertEqual(envelope.kind, .debugPhaseUpdate)
        XCTAssertTrue(envelope.events.contains {
            if case .debugPhaseUpdate(let phase, let detail) = $0 {
                return phase == .verifying && detail == "Running focused checks"
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

}
