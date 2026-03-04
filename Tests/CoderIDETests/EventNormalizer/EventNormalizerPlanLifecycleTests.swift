import XCTest
@testable import CoderIDE

final class EventNormalizerPlanLifecycleTests: XCTestCase {
    func testPlanCreateEmitsTypedEventAndPlanningActivity() {
        let events = EventNormalizer.normalize(
            type: "plan_create",
            payload: [
                "goal": "Implementare panel plan",
                "chosen_path": "Approccio A",
                "conversation_id": "11111111-1111-1111-1111-111111111111",
                "steps": #"[{"step_id":"1","title":"Analisi","status":"completed"}]"#,
            ]
        )

        XCTAssertTrue(events.contains {
            if case .planCreate(let goal, let chosenPath, let steps, let conversationId) = $0 {
                return goal == "Implementare panel plan"
                    && chosenPath == "Approccio A"
                    && conversationId == "11111111-1111-1111-1111-111111111111"
                    && steps.first?.status == .done
            }
            return false
        })

        XCTAssertTrue(events.contains {
            if case .taskActivity(let activity) = $0 {
                return activity.type == "plan_create" && activity.phase == .planning
            }
            return false
        })
    }

    func testPlanStepUpsertParsesMetadataAndRunningState() {
        let events = EventNormalizer.normalize(
            type: "plan_step_upsert",
            payload: [
                "step_id": "2",
                "status": "in_progress",
                "title": "Patch mapper",
                "linked_files": #"["Sources/A.swift","Sources/B.swift"]"#,
                "depends_on": #"["1"]"#,
                "notes": "aggiornare eventi",
            ]
        )

        XCTAssertTrue(events.contains {
            if case .planStepUpsert(let payload) = $0 {
                return payload.stepId == "2"
                    && payload.status == .running
                    && payload.linkedFiles.count == 2
                    && payload.dependsOn == ["1"]
            }
            return false
        })
        XCTAssertTrue(events.contains {
            if case .taskActivity(let activity) = $0 {
                return activity.type == "plan_step_upsert" && activity.isRunning
            }
            return false
        })
    }

    func testPlanStepBatchUpdateEmitsTypedBatchPayload() {
        let events = EventNormalizer.normalize(
            type: "plan_step_batch_update",
            payload: [
                "updates": #"[{"step_id":"1","status":"done"},{"step_id":"2","status":"running"}]"#,
                "conversation_id": "22222222-2222-2222-2222-222222222222"
            ]
        )

        XCTAssertTrue(events.contains {
            if case .planStepBatchUpdate(let items, let conversationId) = $0 {
                return items.count == 2
                    && items[0].status == .done
                    && items[1].status == .running
                    && conversationId == "22222222-2222-2222-2222-222222222222"
            }
            return false
        })
    }

    func testPlanStepReorderAndDependenciesEmitTypedEvents() {
        let reorderEvents = EventNormalizer.normalize(
            type: "plan_step_reorder",
            payload: [
                "ordered_step_ids": #"["2","1","3"]"#
            ]
        )

        XCTAssertTrue(reorderEvents.contains {
            if case .planStepReorder(let orderedStepIds, _) = $0 {
                return orderedStepIds == ["2", "1", "3"]
            }
            return false
        })

        let dependencyEvents = EventNormalizer.normalize(
            type: "plan_step_dependency_set",
            payload: [
                "step_id": "3",
                "depends_on": #"["1","2"]"#
            ]
        )

        XCTAssertTrue(dependencyEvents.contains {
            if case .planStepDependencySet(let stepId, let dependsOn, _) = $0 {
                return stepId == "3" && dependsOn == ["1", "2"]
            }
            return false
        })
    }

    func testPlanSetWalkthroughNormalizesOutcome() {
        let events = EventNormalizer.normalize(
            type: "plan_set_walkthrough",
            payload: [
                "markdown": "## Recap\nDone",
                "summary": "Completato",
                "outcome": "unknown"
            ]
        )

        XCTAssertTrue(events.contains {
            if case .planSetWalkthrough(let markdown, let summary, let outcome, _) = $0 {
                return markdown.contains("Recap")
                    && summary == "Completato"
                    && outcome == "done"
            }
            return false
        })
    }

    func testPlanRequestUserInputParsesStructuredQuestions() {
        let events = EventNormalizer.normalize(
            type: "plan_request_user_input",
            payload: [
                "title": "Clarify scope",
                "phase": "post-analysis",
                "round": "2",
                "context": "Missing deployment constraints",
                "questions": #"[{"id":1,"prompt":"Target environment?","options":[{"label":"iOS only","recommended":true},{"label":"iOS + macOS"}]},{"id":2,"prompt":"Rollout strategy","multi_select":true,"options":["Gradual rollout","Big bang"]}]"#
            ]
        )

        XCTAssertTrue(events.contains {
            if case .planRequestUserInput(let payload) = $0 {
                return payload.questionnaire.questions.count == 2
                    && payload.questionnaire.questions[0].options.count == 2
                    && payload.questionnaire.questions[0].options[0].isRecommended
                    && payload.questionnaire.questions[1].isMultiSelect
                    && payload.round == 2
            }
            return false
        })

        XCTAssertTrue(events.contains {
            if case .taskActivity(let activity) = $0 {
                return activity.type == "plan_request_user_input"
                    && activity.title == "Clarify scope"
                    && activity.phase == .planning
            }
            return false
        })
    }

    func testPlanDiffWithoutFromSnapshotEmitsValidationActivity() {
        let events = EventNormalizer.normalize(
            type: "plan_diff",
            payload: [:]
        )

        guard case .taskActivity(let activity)? = events.first else {
            XCTFail("Expected taskActivity fallback")
            return
        }
        XCTAssertEqual(activity.type, "plan_diff")
        XCTAssertTrue((activity.detail ?? "").contains("Invalid"))
    }
}
