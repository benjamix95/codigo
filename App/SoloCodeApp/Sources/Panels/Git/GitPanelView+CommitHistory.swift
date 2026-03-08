import SwiftUI

extension GitPanelView {
    // MARK: - Commit History

    var commitHistorySection: some View {
        VStack(spacing: 0) {
            if store.commitLog.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("No commits")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 40)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(store.commitLog) { entry in
                            commitRow(entry)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func commitRow(_ entry: GitLogEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                Circle()
                    .fill(DesignSystem.Colors.agentColor.opacity(0.6))
                    .frame(width: 8, height: 8)
                    .padding(.top, 5)
                Rectangle()
                    .fill(DesignSystem.Colors.borderSubtle)
                    .frame(width: 1)
            }
            .frame(width: 8)

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.subject)
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                HStack(spacing: 6) {
                    Text(entry.shortSha)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(DesignSystem.Colors.agentColor.opacity(0.7))
                    Text("·").foregroundStyle(.tertiary)
                    Text(entry.authorName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text("·").foregroundStyle(.tertiary)
                    Text(entry.relativeDate)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .hoverHighlight(Color.primary.opacity(0.04))
    }
}

