import Foundation

struct PlanOutputClassification: Equatable {
    let hasClarificationQuestions: Bool
    let hasStrictOptions: Bool
    let nextPhase: PlanFlowPhase
    let planningState: PlanningState?
}

enum PlanOutputClassifier {
    static func classify(
        fullText: String,
        current: PlanFlowPhase,
        coderMode: CoderMode,
        shouldRunPlanInline: Bool
    ) -> PlanOutputClassification {
        guard coderMode == .plan || shouldRunPlanInline else {
            return PlanOutputClassification(
                hasClarificationQuestions: false,
                hasStrictOptions: false,
                nextPhase: current,
                planningState: nil
            )
        }

        // During the build phase output should not be re-classified — it
        // is execution output, not plan content.
        guard current != .building else {
            return PlanOutputClassification(
                hasClarificationQuestions: false,
                hasStrictOptions: false,
                nextPhase: current,
                planningState: nil
            )
        }

        let clarifications = PlanOptionsParser.parseClarificationQuestions(from: fullText) ?? []
        let strictOptions = PlanOptionsParser.parseStrict(from: fullText)
        let strictTodoCompliant = PlanOptionsParser.todoCompliantOptions(from: strictOptions)
        let hasClarificationQuestions = !clarifications.isEmpty
        let hasStrictOptions = !strictOptions.isEmpty && strictTodoCompliant.count == strictOptions.count

        // Clarification questions always take priority over options.
        // LLMs should never combine ## Questions and ## Options in the same
        // response, but if they do, route to clarification first.
        if hasClarificationQuestions {
            return PlanOutputClassification(
                hasClarificationQuestions: true,
                hasStrictOptions: hasStrictOptions,
                nextPhase: .questioning,
                planningState: .awaitingClarification(questions: fullText)
            )
        }

        if hasStrictOptions {
            return PlanOutputClassification(
                hasClarificationQuestions: false,
                hasStrictOptions: true,
                nextPhase: .proposalReady,
                planningState: .awaitingChoice(planContent: fullText, options: strictTodoCompliant)
            )
        }

        let trimmed = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let fallbackOptions = PlanOptionsParser.parse(from: fullText)
            let fallbackTodoCompliant = PlanOptionsParser.todoCompliantOptions(from: fallbackOptions)
            if !fallbackOptions.isEmpty, fallbackTodoCompliant.count == fallbackOptions.count {
                return PlanOutputClassification(
                    hasClarificationQuestions: false,
                    hasStrictOptions: false,
                    nextPhase: .proposalReady,
                    planningState: .awaitingChoice(planContent: fullText, options: fallbackTodoCompliant)
                )
            }
        }

        return PlanOutputClassification(
            hasClarificationQuestions: false,
            hasStrictOptions: false,
            nextPhase: current,
            planningState: nil
        )
    }
}
