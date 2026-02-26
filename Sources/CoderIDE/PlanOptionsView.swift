import SwiftUI

/// Card showing clarification questions and asking the user to answer in the composer.
struct PlanClarificationView: View {
    let questions: String
    let planColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(planColor)
                Text("Clarification questions")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            MarkdownContentView(
                content: questions,
                context: nil,
                onFileClicked: { _ in },
                textAlignment: .leading
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("Reply in the chat below to continue.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(planColor.opacity(0.3), lineWidth: 0.5)
        )
    }
}

struct PlanClarificationWizardView: View {
    private enum FocusField: Hashable {
        case customQuestion(Int)
        case finalNote
    }

    let questionnaire: PlanClarificationQuestionnaire
    let planColor: Color
    let onSubmit: (PlanClarificationSubmission) -> Void

    @State private var currentQuestionIndex: Int = 0
    @State private var selectedOptionByQuestionId: [Int: String] = [:]
    @State private var customTextByQuestionId: [Int: String] = [:]
    @State private var finalNote: String = ""
    @State private var isConfirmStep = false
    @FocusState private var focusedField: FocusField?

    private var orderedQuestions: [PlanClarificationQuestion] {
        questionnaire.questions.sorted(by: { $0.id < $1.id })
    }

    private var currentQuestion: PlanClarificationQuestion? {
        guard orderedQuestions.indices.contains(currentQuestionIndex) else { return nil }
        return orderedQuestions[currentQuestionIndex]
    }

    private var trimmedFinalNote: String {
        finalNote.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(planColor)
                Text("Questions")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if !isConfirmStep {
                    Text("\(min(currentQuestionIndex + 1, orderedQuestions.count)) of \(orderedQuestions.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }

            if isConfirmStep {
                confirmContent
            } else if let question = currentQuestion {
                questionContent(question)
            } else {
                Text("Questionnaire unavailable.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(planColor.opacity(0.3), lineWidth: 0.5)
        )
        .onChange(of: isConfirmStep) { _, newValue in
            guard newValue else { return }
            Task { @MainActor in
                focusedField = .finalNote
            }
        }
    }

    @ViewBuilder
    private func questionContent(_ question: PlanClarificationQuestion) -> some View {
        Text(question.prompt)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)

        VStack(alignment: .leading, spacing: 8) {
            ForEach(question.options) { option in
                let isSelected = selectedOptionByQuestionId[question.id] == option.id
                Button {
                    handleOptionSelection(option, for: question)
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Text(option.id)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(isSelected ? .white : planColor)
                            .frame(width: 22, height: 22)
                            .background(
                                isSelected ? AnyShapeStyle(planColor) : AnyShapeStyle(planColor.opacity(0.12)),
                                in: Circle()
                            )
                        Text(option.text)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
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
                Text("Custom response (overrides selection)")
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

    private var confirmContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Final confirmation")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            ForEach(orderedQuestions) { question in
                let selectedId = selectedOptionByQuestionId[question.id]
                let selected = question.options.first(where: { $0.id == selectedId })
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(question.id). \(question.prompt)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    if let selected {
                        Text("Selected answer: \(selected.id)) \(selected.text)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.primary)
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

    private func selectedOption(for question: PlanClarificationQuestion) -> PlanClarificationOption? {
        guard let selectedId = selectedOptionByQuestionId[question.id] else { return nil }
        return question.options.first(where: { $0.id == selectedId })
    }

    private func shouldShowCustomField(for question: PlanClarificationQuestion) -> Bool {
        guard let selectedOption = selectedOption(for: question) else { return false }
        return PlanOptionsParser.isOtherLikeClarificationOption(selectedOption)
    }

    private func isLastQuestion(_ question: PlanClarificationQuestion) -> Bool {
        guard let lastQuestionId = orderedQuestions.last?.id else { return false }
        return question.id == lastQuestionId
    }

    private func handleOptionSelection(
        _ option: PlanClarificationOption,
        for question: PlanClarificationQuestion
    ) {
        selectedOptionByQuestionId[question.id] = option.id
        if PlanOptionsParser.isOtherLikeClarificationOption(option) {
            focusedField = .customQuestion(question.id)
        } else {
            customTextByQuestionId[question.id] = ""
            if focusedField == .customQuestion(question.id) {
                focusedField = nil
            }
        }

        Task { @MainActor in
            guard currentQuestion?.id == question.id else { return }
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
            guard let optionId = selectedOptionByQuestionId[question.id],
                  let option = question.options.first(where: { $0.id == optionId }) else {
                return nil
            }
            let customText = customTextByQuestionId[question.id]?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let customResponse = PlanOptionsParser.isOtherLikeClarificationOption(option)
                ? (customText.isEmpty ? nil : customText)
                : nil
            return PlanClarificationAnswer(
                questionId: question.id,
                question: question.prompt,
                optionId: option.id,
                optionText: option.text,
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
        selectedOption(for: question) != nil
    }
}

struct PlanOptionsView: View {
    let options: [PlanOption]
    let selectedOptionId: Int?
    let onSelectOption: (PlanOption) -> Void
    let onCustomResponse: (String) -> Void
    let planColor: Color

    @State private var customText = ""
    @State private var tappedOptionId: Int?
    @FocusState private var isCustomFocused: Bool

    init(
        options: [PlanOption],
        selectedOptionId: Int? = nil,
        planColor: Color = .blue,
        onSelectOption: @escaping (PlanOption) -> Void,
        onCustomResponse: @escaping (String) -> Void
    ) {
        self.options = options
        self.selectedOptionId = selectedOptionId
        self.planColor = planColor
        self.onSelectOption = onSelectOption
        self.onCustomResponse = onCustomResponse
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Choose an option or add a custom response")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            ForEach(options) { opt in
                let isSelected = selectedOptionId == opt.id
                let isTapped = tappedOptionId == opt.id
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        tappedOptionId = opt.id
                    }
                    onSelectOption(opt)
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(opt.id)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white)
                            .frame(width: 22, height: 22)
                            .background(planColor, in: Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text(opt.title)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(2)
                            if opt.fullText != opt.title, opt.fullText.count > opt.title.count + 20 {
                                Text(opt.fullText)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Image(systemName: "arrow.right.circle")
                            .font(.subheadline)
                            .foregroundStyle(isSelected ? planColor : planColor.opacity(0.7))
                    }
                    .padding(10)
                    .background(
                        ((isSelected || isTapped) ? planColor.opacity(0.10) : Color(nsColor: .controlBackgroundColor)),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                (isSelected || isTapped) ? planColor.opacity(0.65) : Color(nsColor: .separatorColor),
                                lineWidth: (isSelected || isTapped) ? 1.0 : 0.5
                            )
                    )
                    .opacity(isTapped ? 0.85 : 1.0)
                    .scaleEffect(isTapped ? 0.98 : 1.0)
                }
                .buttonStyle(.plain)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Custom response")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(alignment: .bottom, spacing: 6) {
                    TextField("Write your response...", text: $customText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)
                        .focused($isCustomFocused)

                    Button {
                        let t = customText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !t.isEmpty else { return }
                        onCustomResponse(t)
                        customText = ""
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(customText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary : planColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(customText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }
}

struct PlanBoardView: View {
    let board: PlanBoard
    let onSelectOption: (PlanOption) -> Void

    private var progress: Double {
        guard !board.steps.isEmpty else { return 0 }
        let done = Double(board.steps.filter { $0.status == .done }.count)
        return done / Double(board.steps.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Built Plan")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(board.goal)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(2)

            ProgressView(value: progress)
                .progressViewStyle(.linear)

            if !board.options.isEmpty {
                Text("Options")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                ForEach(board.options.prefix(3)) { option in
                    Button {
                        onSelectOption(option)
                    } label: {
                        HStack {
                            Text("\(option.id). \(option.title)")
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                            Spacer()
                            if board.chosenPath == option.fullText {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Text("Execution Steps")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            ForEach(board.steps.prefix(8)) { step in
                HStack(spacing: 6) {
                    Circle()
                        .fill(color(for: step.status))
                        .frame(width: 7, height: 7)
                    Text(step.title)
                        .font(.system(size: 11))
                        .lineLimit(1)
                    Spacer()
                    Text(step.status.rawValue)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }

    private func color(for status: PlanStepStatus) -> Color {
        switch status {
        case .pending: return .secondary
        case .running: return .orange
        case .done: return .green
        case .failed: return .red
        }
    }
}
