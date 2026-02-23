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

        let clarifications = PlanOptionsParser.parseClarificationQuestions(from: fullText) ?? []
        let options = PlanOptionsParser.parseStrict(from: fullText)
        let hasClarificationQuestions = !clarifications.isEmpty
        let hasStrictOptions = !options.isEmpty

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
                planningState: .awaitingChoice(planContent: fullText, options: options)
            )
        }

        let trimmed = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let fallbackOptions = PlanOptionsParser.parse(from: fullText)
            if !fallbackOptions.isEmpty {
                return PlanOutputClassification(
                    hasClarificationQuestions: false,
                    hasStrictOptions: false,
                    nextPhase: .proposalReady,
                    planningState: .awaitingChoice(planContent: fullText, options: fallbackOptions)
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
