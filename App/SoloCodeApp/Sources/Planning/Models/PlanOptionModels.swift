import Foundation

/// Option extracted from an AI-generated plan.
struct PlanOption: Identifiable, Equatable, Codable {
    let id: Int
    let title: String
    let fullText: String
}

struct PlanClarificationOption: Identifiable, Equatable, Codable, Hashable {
    let id: String
    let text: String
    let isRecommended: Bool

    init(id: String, text: String, isRecommended: Bool = false) {
        self.id = id
        self.text = text
        self.isRecommended = isRecommended
    }
}

struct PlanClarificationQuestion: Identifiable, Equatable, Codable {
    let id: Int
    let prompt: String
    let options: [PlanClarificationOption]
    let isMultiSelect: Bool

    init(
        id: Int,
        prompt: String,
        options: [PlanClarificationOption],
        isMultiSelect: Bool = false
    ) {
        self.id = id
        self.prompt = prompt
        self.options = options
        self.isMultiSelect = isMultiSelect
    }
}

struct PlanClarificationQuestionnaire: Equatable, Codable {
    let questions: [PlanClarificationQuestion]
}

struct PlanClarificationAnswer: Identifiable, Equatable {
    let questionId: Int
    let question: String
    /// Primary selected option (first selection for multi-select, single for single-select)
    let optionId: String
    let optionText: String
    /// All selected option IDs (for multi-select questions)
    let optionIds: [String]
    /// All selected option texts (for multi-select questions)
    let optionTexts: [String]
    let customResponse: String?

    var id: Int { questionId }

    /// Convenience init for single-select backward compatibility.
    init(
        questionId: Int,
        question: String,
        optionId: String,
        optionText: String,
        customResponse: String?
    ) {
        self.questionId = questionId
        self.question = question
        self.optionId = optionId
        self.optionText = optionText
        self.optionIds = [optionId]
        self.optionTexts = [optionText]
        self.customResponse = customResponse
    }

    /// Full init for multi-select.
    init(
        questionId: Int,
        question: String,
        optionId: String,
        optionText: String,
        optionIds: [String],
        optionTexts: [String],
        customResponse: String?
    ) {
        self.questionId = questionId
        self.question = question
        self.optionId = optionId
        self.optionText = optionText
        self.optionIds = optionIds
        self.optionTexts = optionTexts
        self.customResponse = customResponse
    }
}

struct PlanClarificationSubmission: Equatable {
    let answers: [PlanClarificationAnswer]
    let finalNote: String
}
