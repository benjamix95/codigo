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

        if hasStrictOptions {
            return PlanOutputClassification(
                hasClarificationQuestions: hasClarificationQuestions,
                hasStrictOptions: true,
                nextPhase: .proposalReady,
                planningState: .awaitingChoice(planContent: fullText, options: options)
            )
        }

        if hasClarificationQuestions {
            return PlanOutputClassification(
                hasClarificationQuestions: true,
                hasStrictOptions: false,
                nextPhase: .awaitingClarification,
                planningState: .awaitingClarification(questions: fullText)
            )
        }

        return PlanOutputClassification(
            hasClarificationQuestions: false,
            hasStrictOptions: false,
            nextPhase: current,
            planningState: nil
        )
    }
}
