import XCTest
@testable import CoderIDE

extension EventNormalizerPlanLifecycleTests {
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

    func testPlanRequestUserInputParsesCamelCaseMultiSelectAliases() {
        let events = EventNormalizer.normalize(
            type: "plan_request_user_input",
            payload: [
                "questions": #"[{"id":1,"prompt":"Componenti da includere","multiSelect":true,"options":["API","UI"]},{"id":2,"prompt":"Canali di rilascio","allowMultiple":"true","options":[{"label":"Beta"},{"label":"Stable"}]}]"#,
            ]
        )

        XCTAssertTrue(events.contains {
            if case .planRequestUserInput(let payload) = $0 {
                guard payload.questionnaire.questions.count == 2 else { return false }
                return payload.questionnaire.questions[0].isMultiSelect
                    && payload.questionnaire.questions[1].isMultiSelect
            }
            return false
        })
    }
}
