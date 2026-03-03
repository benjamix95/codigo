import SwiftUI

struct PlanClarificationWizardView: View {
    enum FocusField: Hashable {
        case customQuestion(Int)
        case finalNote
    }

    let questionnaire: PlanClarificationQuestionnaire
    let planColor: Color
    let onSubmit: (PlanClarificationSubmission) -> Void

    @State var currentQuestionIndex: Int = 0
    /// Stores selected option IDs per question. For single-select: set with one element. For multi-select: set with multiple.
    @State var selectedOptionsByQuestionId: [Int: Set<String>] = [:]
    @State var customTextByQuestionId: [Int: String] = [:]
    @State var finalNote: String = ""
    @State var isConfirmStep = false
    @FocusState var focusedField: FocusField?

    var orderedQuestions: [PlanClarificationQuestion] {
        questionnaire.questions.sorted(by: { $0.id < $1.id })
    }

    var currentQuestion: PlanClarificationQuestion? {
        guard orderedQuestions.indices.contains(currentQuestionIndex) else { return nil }
        return orderedQuestions[currentQuestionIndex]
    }

    var trimmedFinalNote: String {
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
                .strokeBorder(planColor.opacity(0.3), lineWidth: 0.5)
        )
        .onChange(of: isConfirmStep) { _, newValue in
            guard newValue else { return }
            Task { @MainActor in
                focusedField = .finalNote
            }
        }
    }
}
