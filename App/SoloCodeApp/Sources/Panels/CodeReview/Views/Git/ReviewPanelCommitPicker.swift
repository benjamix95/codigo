import CoderEngine
import SwiftUI

/// Multi-select commit picker for reviewing specific commits.
struct ReviewPanelCommitPicker: View {
    @ObservedObject var store: CodeReviewPanelStore
    let showsReviewButton: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if store.isLoadingGit {
                HStack {
                    Spacer()
                    ProgressView().controlSize(.small)
                    Spacer()
                }
                .padding(.vertical, 12)
            } else if store.gitCommitLog.isEmpty {
                emptyState
            } else {
                commitList
            }

            if showsReviewButton && !store.selectedCommits.isEmpty {
                reviewButton
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(DesignSystem.Colors.border.opacity(0.4), lineWidth: 0.5)
        )
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "number")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(store.accent)
            Text("COMMITS")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.tertiary)
                .tracking(0.8)

            if !store.selectedCommits.isEmpty {
                Text("\(store.selectedCommits.count)")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(store.accent)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(store.accent.opacity(0.12), in: Capsule())
            }

            Spacer()

            if !store.selectedCommits.isEmpty {
                Button {
                    store.clearCommitSelection()
                } label: {
                    Text("Clear")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Commit List

    private var commitList: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(spacing: 2) {
                    ForEach(store.gitCommitLog, id: \.sha) { entry in
                        commitRow(entry)
                    }
                }
            }
            .frame(maxHeight: 200)

            // Load more button
            if store.gitCommitLog.count >= 50 {
                Button {
                    Task { await store.loadMoreCommits(limit: 200) }
                } label: {
                    Text("Load more commits...")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(store.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func commitRow(_ entry: GitLogEntry) -> some View {
        let isSelected = store.isCommitSelected(entry.sha)

        return Button {
            store.toggleCommitSelection(entry.sha)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? store.accent : Color.secondary.opacity(0.4))

                Text(entry.shortSha)
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(store.accent)
                    .frame(width: 55, alignment: .leading)

                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.subject)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.85))
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(entry.authorName)
                            .font(.system(size: 8.5))
                            .foregroundStyle(.quaternary)
                        Text(entry.relativeDate)
                            .font(.system(size: 8.5))
                            .foregroundStyle(.quaternary)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isSelected ? store.accent.opacity(0.08) : .clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Review Button

    private var reviewButton: some View {
                Button {
                    Task {
                        await store.startReview(
                            scope: store.scopeTarget,
                            modes: store.selectedModes
                        )
                    }
                } label: {
            HStack(spacing: 4) {
                Image(systemName: "play.fill")
                    .font(.system(size: 9))
                Text("Review \(store.selectedCommits.count) Commit\(store.selectedCommits.count == 1 ? "" : "s")")
                    .font(.system(size: 10.5, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(store.accent))
        }
        .buttonStyle(.plain)
        .disabled(store.isRunning)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        Text("No commits found")
            .font(.system(size: 10))
            .foregroundStyle(.quaternary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
    }
}
