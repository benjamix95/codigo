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
                .strokeBorder(planColor.opacity(0.3), lineWidth: 0.5)
        )
    }
}
