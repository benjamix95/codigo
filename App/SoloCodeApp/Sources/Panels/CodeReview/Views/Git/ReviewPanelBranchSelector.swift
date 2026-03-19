import CoderEngine
import SwiftUI

/// Branch picker for reviewing against a specific branch.
struct ReviewPanelBranchSelector: View {
    @ObservedObject var store: CodeReviewPanelStore
    let showsReviewButton: Bool
    @State private var showRemote = false
    @State private var searchText = ""

    private var branches: [GitBranch] {
        let source = showRemote ? store.gitRemoteBranches : store.gitBranches
        if searchText.isEmpty { return source }
        return source.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            contentState

            if showsReviewButton && store.selectedBranch != nil {
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(store.accent)
                Text("BRANCH REVIEW")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.8)
                Spacer()
                Button {
                    Task { await store.refreshGitContext() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Local/Remote toggle
            HStack(spacing: 4) {
                segmentButton("Local", selected: !showRemote) { showRemote = false }
                segmentButton("Remote", selected: showRemote) { showRemote = true }
                Spacer()
            }

            // Search
            TextField("Search branches...", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 10))
        }
    }

    @ViewBuilder
    private var contentState: some View {
        switch store.gitContextStatus {
        case .loading:
            HStack {
                Spacer()
                ProgressView().controlSize(.small)
                Spacer()
            }
            .padding(.vertical, 12)
        case .notRepository(let message):
            stateMessage(
                title: "Workspace non Git",
                detail: message,
                showsRetry: false
            )
        case .failed(let message):
            stateMessage(
                title: "Impossibile caricare il contesto Git del panel review",
                detail: message,
                showsRetry: true
            )
        case .idle, .loaded:
            if branches.isEmpty {
                emptyState
            } else {
                branchList
            }
        }
    }

    // MARK: - Branch List

    private var branchList: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(spacing: 2) {
                ForEach(branches, id: \.name) { branch in
                    branchRow(branch)
                }
            }
        }
        .frame(maxHeight: 160)
    }

    private func branchRow(_ branch: GitBranch) -> some View {
        let isSelected = store.selectedBranch?.name == branch.name
        return Button {
            store.selectBranch(branch)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: branch.isCurrent ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 9))
                    .foregroundStyle(branch.isCurrent ? DesignSystem.Colors.success : Color.secondary.opacity(0.4))

                Text(branch.name)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular, design: .monospaced))
                    .foregroundStyle(isSelected ? store.accent : .primary)
                    .lineLimit(1)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(store.accent)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isSelected ? store.accent.opacity(0.1) : .clear)
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
                Text("Review Branch")
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

    // MARK: - Helpers

    private var emptyState: some View {
        Text("Nessun branch disponibile")
            .font(.system(size: 10))
            .foregroundStyle(.quaternary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
    }

    private func stateMessage(
        title: String,
        detail: String,
        showsRetry: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.primary)
            Text(detail)
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if showsRetry {
                Button("Riprova") {
                    Task { await store.refreshGitContext() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(store.accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
    }

    private func segmentButton(
        _ label: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 9.5, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? store.accent : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(selected ? store.accent.opacity(0.14) : .clear)
                )
        }
        .buttonStyle(.plain)
    }
}
