import SwiftUI

struct PrimaryTextBlockView: View {
    let text: String
    let context: ProjectContext?
    let isStreaming: Bool
    let onFileClicked: (String) -> Void

    var body: some View {
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            MarkdownContentView(
                content: text,
                context: context,
                onFileClicked: onFileClicked,
                textAlignment: .leading,
                isStreaming: isStreaming
            )
            .frame(maxWidth: 800, alignment: .leading)
            .padding(.vertical, 4)
        }
    }
}
