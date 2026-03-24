import SwiftUI

extension UsageFooterView {
    var worktreeCreateSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Passa al worktree", systemImage: "arrow.left.arrow.right")
                    .font(.system(size: 20, weight: .bold))
                Spacer()
                Button {
                    wt.showWorktreeSheet = false
                    cancelWorktreeSheetPreparation(resetSheetState: true)
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
                TextField("solocode/feature-x", text: $wt.worktreeBranchDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, weight: .medium))
                    .disabled(worktreeSheetIsLoading || wt.isWorktreeActionInFlight)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Branch base")
                    .font(.system(size: 12, weight: .semibold))
                Picker("Branch base", selection: $wt.worktreeBaseBranchDraft) {
                    ForEach(availableBranchNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(worktreeSheetIsLoading || availableBranchNames.isEmpty || wt.isWorktreeActionInFlight)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Branch target merge")
                    .font(.system(size: 12, weight: .semibold))
                Picker("Branch target merge", selection: $wt.worktreeMergeTargetDraft) {
                    ForEach(availableBranchNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(worktreeSheetIsLoading || availableBranchNames.isEmpty || wt.isWorktreeActionInFlight)
            }

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Auto-merge al ritorno su Local", isOn: $wt.worktreeAutoMergeOnReturn)
                    .toggleStyle(.switch)
                Toggle("Elimina branch dopo merge", isOn: $wt.worktreeDeleteBranchAfterMerge)
                    .toggleStyle(.switch)
                    .disabled(!wt.worktreeAutoMergeOnReturn)
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

            if worktreeSheetIsLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Caricamento configurazione worktree...")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            } else if let error = wt.worktreeErrorMessage, !error.isEmpty {
                Text(error)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.error)
            } else if let status = wt.worktreeStatusMessage, !status.isEmpty {
                Text(status)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.success)
            }

            HStack(spacing: 10) {
                Spacer()
                Button("Annulla") {
                    wt.showWorktreeSheet = false
                    cancelWorktreeSheetPreparation(resetSheetState: true)
                }
                .disabled(wt.isWorktreeActionInFlight)
                Button("Continua") {
                    startWorktreeCreationFromSheet()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isWorktreeSheetSubmissionDisabled)
            }
        }
        .padding(18)
        .frame(width: 520)
        .glassBackground(cornerRadius: 16)
    }
}
