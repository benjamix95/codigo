import SwiftUI

struct InstantGrepCardsView: View {
    let results: [InstantGrepResult]
    let onOpenMatch: (InstantGrepMatch) -> Void
    @State private var expandedCards: Set<UUID> = []

    var body: some View {
        if !results.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Instant Grep")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                ForEach(results.prefix(4)) { result in
                    grepCard(result)
                }
            }
        }
    }

    private func grepCard(_ result: InstantGrepResult) -> some View {
        let isExpanded = expandedCards.contains(result.id)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignSystem.Colors.info)
                Text(result.query)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                Spacer()
                Text("\(result.matchesCount) match\(result.matchesCount == 1 ? "" : "es")")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Button {
                    if isExpanded {
                        expandedCards.remove(result.id)
                    } else {
                        expandedCards.insert(result.id)
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
            }
            Text("Scope: \(result.scope)")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            if isExpanded {
                ForEach(result.matches.prefix(8)) { match in
                    Button {
                        onOpenMatch(match)
                    } label: {
                        HStack(alignment: .top, spacing: 6) {
                            Text("\((match.file as NSString).lastPathComponent):\(match.line)")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(DesignSystem.Colors.info)
                            Text(match.preview)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 9))
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(DesignSystem.Colors.border.opacity(0.8), lineWidth: 0.6)
        )
    }
}

