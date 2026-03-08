import Foundation

extension EventNormalizer {
    static func parsePlanRequestUserInputPayload(
        payload: [String: String]
    ) -> PlanRequestUserInputPayload? {
        guard let questionsRaw = payload["questions"],
              let questionnaire = parsePlanRequestQuestionnaire(raw: questionsRaw) else {
            return nil
        }

        let title = payload["title"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let phase = payload["phase"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let round = payload["round"].flatMap { Int($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        let context = payload["context"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let conversationId = (payload["conversation_id"] ?? payload["conversationId"])?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return PlanRequestUserInputPayload(
            questionnaire: questionnaire,
            title: title?.isEmpty == true ? nil : title,
            phase: phase?.isEmpty == true ? nil : phase,
            round: round,
            context: context?.isEmpty == true ? nil : context,
            conversationId: conversationId?.isEmpty == true ? nil : conversationId
        )
    }
}
