import SwiftUI

extension CodeReviewPanelView {
    // MARK: - Workers Card

    func workersCard(_ workers: [ReviewWorkerRow]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "person.3.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(accent)
                Text("WORKERS")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.8)
                Spacer()
                Text("\(workers.count)")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.quaternary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.primary.opacity(0.06), in: Capsule())
            }

            ForEach(workers, id: \.id) { w in
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(severityColor(w.severity))
                        .frame(width: 2.5)
                        .padding(.vertical, 3)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(w.id.uppercased())
                                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                .foregroundStyle(accent)
                            Spacer(minLength: 4)
                            severityBadge(w.severity)
                        }
                        Text("\(w.fileCount) files")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.quaternary)

                        Text(w.description)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.primary.opacity(0.85))
                            .lineLimit(2)

                        if !w.files.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 4) {
                                    ForEach(Array(w.files.enumerated()), id: \.offset) { _, path in
                                        Button {
                                            onOpenFile(path)
                                        } label: {
                                            Text((path as NSString).lastPathComponent)
                                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                                .foregroundStyle(accent)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(accent.opacity(0.12), in: Capsule())
                                        }
                                        .buttonStyle(.plain)
                                        .help(path)
                                    }
                                }
                            }
                        } else if !w.filesSummary.isEmpty {
                            Text(w.filesSummary)
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.leading, 8)
                    .padding(.vertical, 5)
                    .padding(.trailing, 8)
                }
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(DesignSystem.Colors.border.opacity(0.3), lineWidth: 0.5)
                )
            }
        }
    }

    func severityColor(_ s: String) -> Color {
        switch s.lowercased() {
        case "critical": return DesignSystem.Colors.error
        case "warning": return DesignSystem.Colors.warning
        default: return DesignSystem.Colors.info
        }
    }

    func severityBadge(_ s: String) -> some View {
        let c = severityColor(s)
        return Text(s.capitalized)
            .font(.system(size: 8.5, weight: .bold))
            .foregroundStyle(c)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(c.opacity(0.12), in: Capsule())
    }
}
