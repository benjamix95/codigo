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
        let conversationId = payload["conversation_id"]?.trimmingCharacters(in: .whitespacesAndNewlines)

        return PlanRequestUserInputPayload(
            questionnaire: questionnaire,
            title: title?.isEmpty == true ? nil : title,
            phase: phase?.isEmpty == true ? nil : phase,
            round: round,
            context: context?.isEmpty == true ? nil : context,
            conversationId: conversationId?.isEmpty == true ? nil : conversationId
        )
    }

    private static func parsePlanRequestQuestionnaire(raw: String) -> PlanClarificationQuestionnaire? {
        guard let data = raw.data(using: .utf8),
              let objects = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              !objects.isEmpty else {
            return nil
        }

        var questions: [PlanClarificationQuestion] = []
        for (index, object) in objects.enumerated() {
            guard let parsed = parsePlanRequestQuestionItem(object, fallbackIndex: index + 1) else {
                continue
            }
            questions.append(parsed)
        }

        guard !questions.isEmpty else { return nil }
        return PlanClarificationQuestionnaire(questions: questions)
    }

    private static func parsePlanRequestQuestionItem(
        _ object: [String: Any],
        fallbackIndex: Int
    ) -> PlanClarificationQuestion? {
        let rawPrompt = (
            (object["prompt"] as? String)
                ?? (object["question"] as? String)
                ?? (object["title"] as? String)
                ?? ""
        )
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawPrompt.isEmpty else { return nil }

        let questionId: Int = {
            if let idInt = object["id"] as? Int, idInt > 0 { return idInt }
            if let idString = object["id"] as? String,
               let parsed = Int(idString.trimmingCharacters(in: .whitespacesAndNewlines)),
               parsed > 0 {
                return parsed
            }
            return fallbackIndex
        }()

        let isMultiSelect = parseFlexibleBool(
            object["multi_select"]
                ?? object["allow_multiple"]
                ?? object["is_multi_select"]
        )

        let parsedOptions = parsePlanRequestOptions(object["options"])
        guard parsedOptions.count >= 2 else { return nil }

        return PlanClarificationQuestion(
            id: questionId,
            prompt: rawPrompt,
            options: parsedOptions,
            isMultiSelect: isMultiSelect
        )
    }

    private static func parsePlanRequestOptions(_ raw: Any?) -> [PlanClarificationOption] {
        if let textOptions = raw as? [String] {
            return textOptions.enumerated().compactMap { idx, optionText in
                let trimmed = optionText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return nil }
                return PlanClarificationOption(
                    id: optionLetter(for: idx),
                    text: trimmed
                )
            }
        }

        guard let objectOptions = raw as? [[String: Any]], !objectOptions.isEmpty else {
            return []
        }

        return objectOptions.enumerated().compactMap { idx, option in
            var text = (
                (option["label"] as? String)
                    ?? (option["text"] as? String)
                    ?? (option["title"] as? String)
                    ?? (option["content"] as? String)
                    ?? ""
            )
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let description = (option["description"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !description.isEmpty, !text.isEmpty {
                text = "\(text) (\(description))"
            }
            guard !text.isEmpty else { return nil }

            let recommended = parseFlexibleBool(option["recommended"])
                || text.lowercased().contains("(recommended)")

            let cleanText = text.replacingOccurrences(
                of: #"\s*\((?i:recommended)\)\s*$"#,
                with: "",
                options: .regularExpression
            ).trimmingCharacters(in: .whitespacesAndNewlines)

            return PlanClarificationOption(
                id: optionLetter(for: idx),
                text: cleanText,
                isRecommended: recommended
            )
        }
    }

    private static func optionLetter(for index: Int) -> String {
        let normalizedIndex = max(0, min(index, 25))
        let base: UInt32 = 65
        let scalarValue = base + UInt32(normalizedIndex)
        guard let scalar = UnicodeScalar(scalarValue) else {
            return "A"
        }
        return String(Character(scalar))
    }

    private static func parseFlexibleBool(_ raw: Any?) -> Bool {
        if let boolValue = raw as? Bool {
            return boolValue
        }
        if let intValue = raw as? Int {
            return intValue != 0
        }
        if let number = raw as? NSNumber {
            return number.boolValue
        }
        if let stringValue = raw as? String {
            let normalized = stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized == "true" || normalized == "1" || normalized == "yes" || normalized == "y"
        }
        return false
    }
}
