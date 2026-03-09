import SwiftUI

/// Card for selecting the review scope: uncommitted, staged, against ref, branch, or commits.
struct ReviewPanelScopeCard: View {
    @ObservedObject var store: CodeReviewPanelStore
    @State private var showCommitPicker = false
    @State private var showBranchPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "scope")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(store.accent)
                Text("SCOPE")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.8)
            }

            // Scope type selector
            HStack(spacing: 4) {
                scopeButton("Uncommitted", target: .uncommitted)
                scopeButton("Staged", target: .staged)
                scopeButton("Ref", target: .againstRef(store.againstCommitRef))
                scopeButton("Commits", target: .commits(currentCommitScope))
                scopeButton("Branch", target: .branch(store.selectedBranch?.name ?? ""))
            }

            // Against ref input (only when ref scope is selected)
            if case .againstRef = store.scopeTarget {
                againstRefInput
            }

            if case .commits = store.scopeTarget {
                commitSelectorRow
            }

            if case .branch = store.scopeTarget {
                branchSelectorRow
            }

            // Autofix toggle
            autofixToggle

            // Run button
            runButton
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

    // MARK: - Scope Button

    private func scopeButton(_ label: String, target: ReviewScopeTarget) -> some View {
        let isSelected = scopeMatches(target)
        return Button {
            store.scopeTarget = target
            switch target {
            case .commits:
                store.selectedBranch = nil
                if store.selectedCommits.isEmpty {
                    store.scopeTarget = .commits([])
                }
                showCommitPicker = true
            case .branch:
                store.selectedCommits.removeAll()
                if let branch = store.selectedBranch?.name {
                    store.scopeTarget = .branch(branch)
                } else {
                    store.scopeTarget = .branch("")
                }
                showBranchPicker = true
            default:
                store.selectedBranch = nil
                store.selectedCommits.removeAll()
                showCommitPicker = false
                showBranchPicker = false
            }
        } label: {
            Text(label)
                .font(.system(size: 9.5, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? store.accent : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isSelected ? store.accent.opacity(0.14) : Color.primary.opacity(0.04))
                )
        }
        .buttonStyle(.plain)
    }

    private func scopeMatches(_ target: ReviewScopeTarget) -> Bool {
        switch (store.scopeTarget, target) {
        case (.uncommitted, .uncommitted): return true
        case (.staged, .staged): return true
        case (.againstRef, .againstRef): return true
        case (.commits, .commits): return true
        case (.branch, .branch): return true
        default: return false
        }
    }

    // MARK: - Against Ref Input

    private var againstRefInput: some View {
        HStack(spacing: 6) {
            TextField("HEAD~1, abc123, main..feature", text: $store.againstCommitRef)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .frame(maxWidth: .infinity)
        }
    }

    private var commitSelectorRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "number")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(store.accent)
                Text(commitSelectionLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(store.selectedCommits.isEmpty ? .secondary : store.accent)
                Spacer()
                if !store.selectedCommits.isEmpty {
                    Button("Clear") {
                        store.clearCommitSelection()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                }
                Button("Select Commits") {
                    showCommitPicker = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(store.accent)
                .popover(isPresented: $showCommitPicker, arrowEdge: .bottom) {
                    ReviewPanelCommitPicker(store: store, showsReviewButton: false)
                        .frame(width: 420, height: 320)
                        .padding(10)
                }
            }
            if !store.selectedCommits.isEmpty {
                selectedCommitTokens
            }
        }
    }

    private var branchSelectorRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(store.accent)
            Text(store.selectedBranch?.name ?? "No branch selected")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(store.selectedBranch == nil ? .secondary : store.accent)
                .lineLimit(1)
            Spacer()
            if store.selectedBranch != nil {
                Button("Clear") {
                    store.clearBranchSelection()
                }
                .buttonStyle(.plain)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
            }
            Button("Select Branch") {
                showBranchPicker = true
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(store.accent)
            .popover(isPresented: $showBranchPicker, arrowEdge: .bottom) {
                ReviewPanelBranchSelector(store: store, showsReviewButton: false)
                    .frame(width: 420, height: 320)
                    .padding(10)
            }
        }
    }

    private var selectedCommitTokens: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(selectedCommitDisplayShas, id: \.self) { sha in
                    Text(sha)
                        .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(store.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(store.accent.opacity(0.12), in: Capsule())
                }
            }
        }
    }

    // MARK: - Autofix Toggle

    private var autofixToggle: some View {
        HStack(spacing: 8) {
            Toggle(isOn: Binding(
                get: { !store.settings.analysisOnly },
                set: { store.updatePipelineSettings(analysisOnly: !$0) }
            )) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 9))
                    Text("Autofix")
                        .font(.system(size: 10.5, weight: .medium))
                }
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .disabled(store.isRunning)

            Spacer()

            if !store.settings.analysisOnly {
                Text("max \(store.settings.maxRounds) rounds")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.quaternary)
            }
        }
    }

    // MARK: - Run Button

    private var runButton: some View {
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
                Text("Run Review")
                    .font(.system(size: 10.5, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(store.accent)
            )
        }
        .buttonStyle(.plain)
        .disabled(store.isRunning || !isValidScope)
    }

    private var isValidScope: Bool {
        switch store.scopeTarget {
        case .uncommitted, .staged, .workspace: return true
        case .againstRef(let ref): return !ref.isEmpty
        case .branch(let name): return !name.isEmpty && store.selectedBranch != nil
        case .commits(let shas): return !shas.isEmpty
        }
    }

    private var currentCommitScope: [String] {
        store.gitCommitLog
            .filter { store.selectedCommits.contains($0.sha) }
            .map(\.sha)
    }

    private var selectedCommitDisplayShas: [String] {
        currentCommitScope.map { String($0.prefix(8)) }
    }

    private var commitSelectionLabel: String {
        let count = store.selectedCommits.count
        if count == 0 { return "No commits selected" }
        return count == 1 ? "1 commit selected" : "\(count) commits selected"
    }
}
