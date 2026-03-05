import XCTest
@testable import CoderIDE

extension EventNormalizerPlanLifecycleTests {
    func testPlanCreateBlankGoalFallsBackAndBlankChosenPathBecomesNil() {
        let events = EventNormalizer.normalize(
            type: "plan_create",
            payload: [
                "goal": "   ",
                "chosen_path": "   ",
            ]
        )

        XCTAssertTrue(events.contains {
            if case .planCreate(let goal, let chosenPath, _, _) = $0 {
                return goal == "Operational plan in progress" && chosenPath == nil
            }
            return false
        })

        XCTAssertTrue(events.contains {
            if case .taskActivity(let activity) = $0 {
                return activity.type == "plan_create"
                    && activity.detail == "Operational plan in progress"
            }
            return false
        })
    }

    func testPlanSetWalkthroughBlankSummaryFallsBackToOutcomeDetail() {
        let events = EventNormalizer.normalize(
            type: "plan_set_walkthrough",
            payload: [
                "markdown": "## Recap\nDone",
                "summary": "   ",
                "outcome": "done",
            ]
        )

        XCTAssertTrue(events.contains {
            if case .planSetWalkthrough(_, let summary, let outcome, _) = $0 {
                return summary == nil && outcome == "done"
            }
            return false
        })

        XCTAssertTrue(events.contains {
            if case .taskActivity(let activity) = $0 {
                return activity.type == "plan_set_walkthrough"
                    && activity.detail == "done"
            }
            return false
        })
    }

    func testPlanStepReorderAcceptsCSVFallback() {
        let events = EventNormalizer.normalize(
            type: "plan_step_reorder",
            payload: [
                "ordered_step_ids": "1, 2 ,3"
            ]
        )

        XCTAssertTrue(events.contains {
            if case .planStepReorder(let ids, _) = $0 {
                return ids == ["1", "2", "3"]
            }
            return false
        })
    }

    func testPlanStepDependencySetParsesMixedDependsOnValues() {
        let events = EventNormalizer.normalize(
            type: "plan_step_dependency_set",
            payload: [
                "step_id": "5",
                "depends_on": #"[1,"2",null,true,false,""]"#,
            ]
        )

        XCTAssertTrue(events.contains {
            if case .planStepDependencySet(let stepId, let dependsOn, _) = $0 {
                return stepId == "5"
                    && dependsOn == ["1", "2", "true", "false"]
            }
            return false
        })
    }

    func testPlanStepBatchUpdateParsesNumericStepIdsAndMixedArrays() {
        let events = EventNormalizer.normalize(
            type: "plan_step_batch_update",
            payload: [
                "updates": #"[{"step_id":1,"status":"running","linked_files":["Sources/A.swift",12,true],"depends_on":[2,"3",null]}]"#,
            ]
        )

        XCTAssertTrue(events.contains {
            if case .planStepBatchUpdate(let items, _) = $0 {
                guard let first = items.first else { return false }
                return first.stepId == "1"
                    && first.status == .running
                    && first.linkedFiles == ["Sources/A.swift", "12", "true"]
                    && first.dependsOn == ["2", "3"]
            }
            return false
        })
    }
}
