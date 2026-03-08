import SwiftUI

struct ReviewPanelChatStructuredSectionsView: View {
    let sections: [ReviewPanelChatStructuredSection]
    let accent: Color
    var isStreaming: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(sections) { section in
                sectionView(for: section)
            }
        }
    }

    @ViewBuilder
    private func sectionView(
        for section: ReviewPanelChatStructuredSection
    ) -> some View {
        switch section.style {
        case .thinking:
            ReviewPanelChatThinkingView(
                section: section,
                isStreaming: isStreaming
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        case .activity:
            ReviewPanelChatActivityView(
                section: section,
                accent: accent
            )
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        case .mermaid:
            MermaidDiagramView(
                mermaidCode: section.lines.joined(separator: "\n"),
                accentColor: accent
            )
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        case .outcome:
            ReviewPanelChatOutcomeView(
                section: section,
                accent: accent
            )
        default:
            ReviewPanelChatStructuredSectionView(
                section: section,
                accent: accent
            )
        }
    }
}

private struct ReviewPanelChatStructuredSectionView: View {
    let section: ReviewPanelChatStructuredSection
    let accent: Color
    @State private var isExpanded: Bool

    init(section: ReviewPanelChatStructuredSection, accent: Color) {
        self.section = section
        self.accent = accent
        _isExpanded = State(initialValue: section.isInitiallyExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.snappy(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(accent.opacity(0.8))
                    Text(section.title.uppercased())
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(accent.opacity(0.85))
                        .tracking(0.6)
                    Spacer(minLength: 0)
                    Text("\(section.lines.count)")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(.quaternary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                sectionBody
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.black.opacity(0.22))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(DesignSystem.Colors.border.opacity(0.16), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var sectionBody: some View {
        switch section.style {
        case .prose:
            Text(section.lines.joined(separator: "\n"))
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.92))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .metadata:
            VStack(alignment: .leading, spacing: 4) {
                ForEach(section.displayLines) { line in
                    Text(line.text)
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.80))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        case .findings:
            VStack(alignment: .leading, spacing: 6) {
                ForEach(section.displayLines) { line in
                    HStack(alignment: .top, spacing: 6) {
                        Circle()
                            .fill(accent.opacity(0.55))
                            .frame(width: 5, height: 5)
                            .padding(.top, 4)
                        Text(line.text)
                            .font(.system(size: 9.5))
                            .foregroundStyle(.white.opacity(0.90))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        case .log:
            ReviewPanelChatStructuredLogView(section: section)
        case .thinking, .activity, .mermaid, .outcome:
            // Handled by dedicated views in the parent
            EmptyView()
        }
    }
}
