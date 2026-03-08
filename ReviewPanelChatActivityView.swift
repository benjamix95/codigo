import SwiftUI

/// Compact activity log view for the review panel chat.
/// Shows tool calls, file operations, and other activity in a
/// collapsible section with monospace styling and a tinted bar.
struct ReviewPanelChatActivityView: View {
    let section: ReviewPanelChatStructuredSection
    let accent: Color

    @State private var isExpanded: Bool

    init(
        section: ReviewPanelChatStructuredSection,
        accent: Color
    ) {
        self.section = section
        self.accent = accent
        _isExpanded = State(initialValue: section.isInitiallyExpanded)
    }

    private var activityAccent: Color {
        Color(red: 0.45, green: 0.72, blue: 0.55).opacity(0.7)
    }
    private var headerColor: Color { .primary.opacity(0.35) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(headerColor)
                        .frame(width: 8)
                    Image(systemName: "gearshape.2")
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(activityAccent)
                    Text(section.title.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(headerColor)
                        .tracking(0.5)
                    Spacer(minLength: 0)
                    Text("\(section.lines.count)")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(.quaternary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, isExpanded ? 6 : 0)

            if isExpanded {
                HStack(alignment: .top, spacing: 0) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(activityAccent)
                        .frame(width: 2)
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(section.displayLines) { line in
                            HStack(alignment: .top, spacing: 5) {
                                Circle()
                                    .fill(activityAccent.opacity(0.5))
                                    .frame(width: 4, height: 4)
                                    .padding(.top, 3.5)
                                Text(line.text)
                                    .font(.system(
                                        size: 9,
                                        weight: .regular,
                                        design: .monospaced
                                    ))
                                    .foregroundStyle(.white.opacity(0.65))
                                    .textSelection(.enabled)
                                    .frame(
                                        maxWidth: .infinity,
                                        alignment: .leading
                                    )
                            }
                        }
                    }
                    .padding(.leading, 10)
                }
                .padding(.leading, 3)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}
