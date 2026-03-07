import SwiftUI

extension PlanClarificationWizardView {
    @ViewBuilder
    func questionContent(_ question: PlanClarificationQuestion) -> some View {
        Text(question.prompt)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)

        VStack(alignment: .leading, spacing: 8) {
            ForEach(question.options) { option in
                let isSelected = selectedOptionsByQuestionId[question.id]?.contains(option.id) == true
                Button {
                    handleOptionSelection(option, for: question)
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        if question.isMultiSelect {
                            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(isSelected ? planColor : .secondary)
                                .frame(width: 22, height: 22)
                        } else {
                            Text(option.id)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(
                                    isSelected ? AnyShapeStyle(planColor) : AnyShapeStyle(planColor.opacity(0.12)),
                                    in: Circle()
                                )
                        }
                        HStack(spacing: 5) {
                            Text(option.text)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                            if option.isRecommended {
                                Text("Recommended")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(planColor, in: Capsule())
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(isSelected ? planColor.opacity(0.10) : Color(nsColor: .controlBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(
                                isSelected ? planColor.opacity(0.6) : Color(nsColor: .separatorColor),
                                lineWidth: isSelected ? 1.0 : 0.5
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }

        if shouldShowCustomField(for: question) {
            VStack(alignment: .leading, spacing: 6) {
                Text(question.isMultiSelect ? "Custom response for \"Other\"" : "Custom response (overrides selection)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField(
                    "Write your custom response here...",
                    text: customTextBinding(for: question.id),
                    axis: .vertical
                )
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...5)
                .focused($focusedField, equals: .customQuestion(question.id))
                .submitLabel(isLastQuestion(question) ? .done : .next)
                .onSubmit {
                    advanceFromQuestion(question)
                }
            }
        }

        wizardActions(for: question)
    }

    @ViewBuilder
    private func wizardActions(for question: PlanClarificationQuestion) -> some View {
        let canContinue = isQuestionAnswered(question)
        let isLastQuestion = isLastQuestion(question)
        HStack(spacing: 8) {
            Button("Back") {
                if currentQuestionIndex > 0 {
                    currentQuestionIndex -= 1
                }
            }
            .buttonStyle(.plain)
            .font(.caption.weight(.medium))
            .disabled(currentQuestionIndex == 0)

            Spacer()

            Button(isLastQuestion ? "Go to confirmation" : "Continue") {
                advanceFromQuestion(question)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(planColor)
            .disabled(!canContinue)
        }
    }

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
            && orderedQuestions.allSatisfy(isQuestionAnswered)
    }

    private func customTextBinding(for questionId: Int) -> Binding<String> {
        Binding(
            get: { customTextByQuestionId[questionId] ?? "" },
            set: { customTextByQuestionId[questionId] = $0 }
        )
    }

    /// Returns the first selected option for a question (for single-select compatibility).
    private func selectedOption(for question: PlanClarificationQuestion) -> PlanClarificationOption? {
        guard let selectedIds = selectedOptionsByQuestionId[question.id], let firstId = selectedIds.first else { return nil }
        return question.options.first(where: { $0.id == firstId })
    }

    private func shouldShowCustomField(for question: PlanClarificationQuestion) -> Bool {
        let selectedIds = selectedOptionsByQuestionId[question.id] ?? Set()
        guard !selectedIds.isEmpty else { return false }
        let selected = question.options.filter { selectedIds.contains($0.id) }
        guard !selected.isEmpty else { return false }
        return selected.contains(where: PlanOptionsParser.isOtherLikeClarificationOption)
    }

    private func isLastQuestion(_ question: PlanClarificationQuestion) -> Bool {
        guard let lastQuestionId = orderedQuestions.last?.id else { return false }
        return question.id == lastQuestionId
    }

    private func handleOptionSelection(
        _ option: PlanClarificationOption,
        for question: PlanClarificationQuestion
    ) {
        if question.isMultiSelect {
            // Multi-select: toggle selection.
            var current = selectedOptionsByQuestionId[question.id] ?? Set()
            if current.contains(option.id) {
                current.remove(option.id)
            } else {
                current.insert(option.id)
            }
            selectedOptionsByQuestionId[question.id] = current
            let selectedOptions = question.options.filter { current.contains($0.id) }
            let includesOther = selectedOptions.contains(where: PlanOptionsParser.isOtherLikeClarificationOption)
            if includesOther {
                focusedField = .customQuestion(question.id)
            } else {
                customTextByQuestionId[question.id] = ""
                if focusedField == .customQuestion(question.id) {
                    focusedField = nil
                }
            }
            // Don't auto-advance for multi-select — user must explicitly press Continue.
            return
        }

        // Single-select: replace selection.
        selectedOptionsByQuestionId[question.id] = Set([option.id])
        if PlanOptionsParser.isOtherLikeClarificationOption(option) {
            focusedField = .customQuestion(question.id)
            // Don't auto-advance for "Other" options - user needs to type custom text.
            return
        } else {
            customTextByQuestionId[question.id] = ""
            if focusedField == .customQuestion(question.id) {
                focusedField = nil
            }
        }

        // Only auto-advance for non-"Other" single-select options, and guard against stale state.
        let targetQuestionId = question.id
        Task { @MainActor in
            guard currentQuestion?.id == targetQuestionId else { return }
            advanceFromQuestion(question)
        }
    }

    private func advanceFromQuestion(_ question: PlanClarificationQuestion) {
        guard isQuestionAnswered(question) else { return }
        if isLastQuestion(question) {
            isConfirmStep = true
        } else {
            currentQuestionIndex += 1
            if let nextQuestion = currentQuestion, shouldShowCustomField(for: nextQuestion) {
                focusedField = .customQuestion(nextQuestion.id)
            } else {
                focusedField = nil
            }
        }
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

    private func isQuestionAnswered(_ question: PlanClarificationQuestion) -> Bool {
        isClarificationSelectionComplete(
            question: question,
            selectedOption: selectedOption(for: question),
            selectedOptions: selectedOptionsByQuestionId[question.id],
            customText: customTextByQuestionId[question.id]
        )
    }
}
