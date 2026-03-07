import SwiftUI

/// Card for selecting the review scope: uncommitted, staged, against ref, branch, or commits.
struct ReviewPanelScopeCard: View {
    @ObservedObject var store: CodeReviewPanelStore

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
            }

            // Against ref input (only when ref scope is selected)
            if case .againstRef = store.scopeTarget {
                againstRefInput
            }

            // Branch/Commit info
            if case .branch(let name) = store.scopeTarget {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 9))
                        .foregroundStyle(store.accent)
                    Text(name)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(store.accent)
                    Spacer()
                    Button { store.clearBranchSelection() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.quaternary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if case .commits(let shas) = store.scopeTarget, !shas.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "number")
                        .font(.system(size: 9))
                        .foregroundStyle(store.accent)
                    Text("\(shas.count) commits selected")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(store.accent)
                    Spacer()
                    Button { store.clearCommitSelection() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.quaternary)
                    }
                    .buttonStyle(.plain)
                }
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
            store.selectedBranch = nil
            store.selectedCommits.removeAll()
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
                    mode: store.activeMode
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
        case .uncommitted, .staged: return true
        case .againstRef(let ref): return !ref.isEmpty
        case .branch(let name): return !name.isEmpty
        case .commits(let shas): return !shas.isEmpty
        }
    }
}
