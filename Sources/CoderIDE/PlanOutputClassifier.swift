import Foundation

struct PlanOutputClassification: Equatable {
    let hasClarificationQuestions: Bool
    let hasStrictOptions: Bool
    let nextPhase: PlanFlowPhase
    let planningState: PlanningState?
    let isConfident: Bool
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
                planningState: nil,
                isConfident: false
            )
        }

        // During the build phase output should not be re-classified — it
        // is execution output, not plan content.
        guard current != .building else {
            return PlanOutputClassification(
                hasClarificationQuestions: false,
                hasStrictOptions: false,
                nextPhase: current,
                planningState: nil,
                isConfident: false
            )
        }

        if hasNoQuestionsNeededSignal(fullText) {
            return PlanOutputClassification(
                hasClarificationQuestions: false,
                hasStrictOptions: false,
                nextPhase: .generating,
                planningState: nil,
                isConfident: true
            )
        }

        let clarifications = PlanOptionsParser.parseClarificationQuestions(from: fullText) ?? []
        let hasClarificationQuestions = !clarifications.isEmpty

        // Clarification questions always take priority over options.
        // LLMs should never combine ## Questions and ## Options in the same
        // response, but if they do, route to clarification first.
        if hasClarificationQuestions {
            return PlanOutputClassification(
                hasClarificationQuestions: true,
                hasStrictOptions: false,
                nextPhase: .questioning,
                planningState: .awaitingClarification(questions: fullText),
                isConfident: true
            )
        }

        let strictOptions = PlanOptionsParser.parseStrict(from: fullText)
        let strictTodoCompliant = PlanOptionsParser.todoCompliantOptions(from: strictOptions)
        let hasStrictOptions = !strictOptions.isEmpty && strictTodoCompliant.count == strictOptions.count

        if hasStrictOptions {
            return PlanOutputClassification(
                hasClarificationQuestions: false,
                hasStrictOptions: true,
                nextPhase: .proposalReady,
                planningState: .awaitingChoice(planContent: fullText, options: strictTodoCompliant),
                isConfident: true
            )
        }

        let trimmed = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let fallbackOptions = PlanOptionsParser.parseForPlanClassification(from: fullText)
            let fallbackTodoCompliant = PlanOptionsParser.todoCompliantOptions(from: fallbackOptions)
            if !fallbackOptions.isEmpty, fallbackTodoCompliant.count == fallbackOptions.count {
                return PlanOutputClassification(
                    hasClarificationQuestions: false,
                    hasStrictOptions: false,
                    nextPhase: .proposalReady,
                    planningState: .awaitingChoice(planContent: fullText, options: fallbackTodoCompliant),
                    isConfident: true
                )
            }
        }

        return PlanOutputClassification(
            hasClarificationQuestions: false,
            hasStrictOptions: false,
            nextPhase: current,
            planningState: nil,
            isConfident: false
        )
    }
}
