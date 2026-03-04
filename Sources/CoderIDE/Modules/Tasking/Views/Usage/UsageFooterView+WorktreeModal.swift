import SwiftUI

extension UsageFooterView {
    var worktreeCreateSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Passa al worktree", systemImage: "arrow.left.arrow.right")
                    .font(.system(size: 20, weight: .bold))
                Spacer()
                Button {
                    showWorktreeSheet = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Text("Scegli il branch worktree e le opzioni di merge automatico.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Ramo del worktree")
                    .font(.system(size: 12, weight: .semibold))
                TextField("solocode/feature-x", text: $worktreeBranchDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, weight: .medium))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Branch target merge")
                    .font(.system(size: 12, weight: .semibold))
                Picker("Branch target merge", selection: $worktreeMergeTargetDraft) {
                    ForEach(availableBranchNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Auto-merge al ritorno su Local", isOn: $worktreeAutoMergeOnReturn)
                    .toggleStyle(.switch)
                Toggle("Elimina branch dopo merge", isOn: $worktreeDeleteBranchAfterMerge)
                    .toggleStyle(.switch)
                    .disabled(!worktreeAutoMergeOnReturn)
            }

            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal")
                    .foregroundStyle(DesignSystem.Colors.agentColor)
                Text("Prima di ogni auto-commit: fix automatici + test verdi (quality gate).")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

            if let error = worktreeErrorMessage, !error.isEmpty {
                Text(error)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.error)
            } else if let status = worktreeStatusMessage, !status.isEmpty {
                Text(status)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.success)
            }

            HStack(spacing: 10) {
                Spacer()
                Button("Annulla") {
                    showWorktreeSheet = false
                }
                .disabled(isWorktreeActionInFlight)
                Button("Continua") {
                    startWorktreeCreationFromSheet()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    isWorktreeActionInFlight
                        || worktreeBranchDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || worktreeMergeTargetDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
        .padding(18)
        .frame(width: 520)
        .glassBackground(cornerRadius: 16)
    }
}
