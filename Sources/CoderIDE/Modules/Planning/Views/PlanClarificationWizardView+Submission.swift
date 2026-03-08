import SwiftUI

extension PlanClarificationWizardView {
    var confirmContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Final confirmation")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            ForEach(orderedQuestions) { question in
                let selectedIds = selectedOptionsByQuestionId[question.id] ?? Set<String>()
                let selectedOptions = question.options.filter { selectedIds.contains($0.id) }
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(question.id). \(question.prompt)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    if !selectedOptions.isEmpty {
                        if question.isMultiSelect {
                            let selectedText = selectedOptions.map { "\($0.id)) \($0.text)" }.joined(separator: ", ")
                            Text("Selected: \(selectedText)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.primary)
                        } else if let selected = selectedOptions.first {
                            Text("Selected answer: \(selected.id)) \(selected.text)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.primary)
                        }
                        let custom = customTextByQuestionId[question.id]?
                            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                        if !custom.isEmpty {
                            Text("Custom response (overrides selection): \(custom)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(planColor)
                        }
                    } else {
                        Text("Answer: not selected")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Final note (optional)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField(
                    "Add final details for the plan (optional)...",
                    text: $finalNote,
                    axis: .vertical
                )
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...6)
                .focused($focusedField, equals: .finalNote)
                .submitLabel(.done)
                .onSubmit {
                    submitIfPossible()
                }
            }

            HStack(spacing: 8) {
                Button("Back to questions") {
                    isConfirmStep = false
                    if let question = currentQuestion, shouldShowCustomField(for: question) {
                        focusedField = .customQuestion(question.id)
                    } else {
                        focusedField = nil
                    }
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))

                Spacer()

                Button("Final confirmation") {
                    submitIfPossible()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(planColor)
                .disabled(!canSubmitFinal)
            }
        }
    }

    private var canSubmitFinal: Bool {
        !orderedQuestions.isEmpty
            && orderedQuestions.allSatisfy { isQuestionAnswered($0) }
    }

    private func buildSubmission() -> PlanClarificationSubmission? {
        let answers = orderedQuestions.compactMap { question -> PlanClarificationAnswer? in
            guard let selectedIds = selectedOptionsByQuestionId[question.id], !selectedIds.isEmpty else {
                return nil
            }
            let selectedOptions = question.options.filter { selectedIds.contains($0.id) }
            guard !selectedOptions.isEmpty else { return nil }

            guard let primaryOption = selectedOptions.first else { return nil }
            let customText = customTextByQuestionId[question.id]?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let includesOther = selectedOptions.contains(where: PlanOptionsParser.isOtherLikeClarificationOption)
            let customResponse: String? = includesOther ? (customText.isEmpty ? nil : customText) : nil
            return PlanClarificationAnswer(
                questionId: question.id,
                question: question.prompt,
                optionId: primaryOption.id,
                optionText: primaryOption.text,
                optionIds: selectedOptions.map(\.id),
                optionTexts: selectedOptions.map(\.text),
                customResponse: customResponse
            )
        }
        guard answers.count == orderedQuestions.count else { return nil }
        return PlanClarificationSubmission(
            answers: answers,
            finalNote: trimmedFinalNote
        )
    }

    private func submitIfPossible() {
        guard let submission = buildSubmission() else { return }
        onSubmit(submission)
        isConfirmStep = false
        focusedField = nil
    }
}
