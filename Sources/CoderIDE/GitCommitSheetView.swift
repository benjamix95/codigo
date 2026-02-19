import SwiftUI

enum GitCommitNextStep: String, CaseIterable, Identifiable {
    case commit
    case commitAndPush
    case commitAndCreatePR

    var id: String { rawValue }

    var label: String {
        switch self {
        case .commit: return "Commit"
        case .commitAndPush: return "Commit and push"
        case .commitAndCreatePR: return "Commit and create PR"
        }
    }
}

struct GitCommitSheetView: View {
    let branch: String
    let status: GitStatusSummary
    let canCreatePR: Bool
    @Binding var includeUnstaged: Bool
    @Binding var commitMessage: String
    @Binding var nextStep: GitCommitNextStep
    let isBusy: Bool
    let errorText: String?
    let onClose: () -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Commit your changes")
                    .font(.system(size: 28, weight: .bold))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
            }

            HStack {
                Text("Branch")
                    .font(.system(size: 20, weight: .semibold))
                Spacer()
                Label(branch, systemImage: "arrow.triangle.branch")
                    .font(.system(size: 18, weight: .medium))
            }

            HStack(spacing: 14) {
                Text("Changes")
                    .font(.system(size: 20, weight: .semibold))
                Spacer()
                Text("\(status.changedFiles) files")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("+\(status.added + status.untracked)")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.success)
                Text("-\(status.removed)")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.error)
            }

            Toggle("Include unstaged", isOn: $includeUnstaged)
                .toggleStyle(.switch)
                .disabled(isBusy)
                .font(.system(size: 16, weight: .medium))

            VStack(alignment: .leading, spacing: 8) {
                Text("Commit message")
                    .font(.system(size: 20, weight: .semibold))
                TextField("Leave blank to autogenerate a commit message", text: $commitMessage, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(DesignSystem.Colors.borderSubtle, lineWidth: 0.8)
                    )
                    .lineLimit(1...4)
                    .disabled(isBusy)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Next steps")
                    .font(.system(size: 20, weight: .semibold))
                ForEach(GitCommitNextStep.allCases) { step in
                    Button {
                        if step == .commitAndCreatePR && !canCreatePR { return }
                        nextStep = step
                    } label: {
                        HStack {
                            Text(step.label)
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle((step == .commitAndCreatePR && !canCreatePR) ? .tertiary : .primary)
                            Spacer()
                            if nextStep == step {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .disabled((step == .commitAndCreatePR && !canCreatePR) || isBusy)
                }
            }

            if let errorText, !errorText.isEmpty {
                Text(errorText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.error)
            }

            Button(action: onContinue) {
                HStack {
                    if isBusy {
                        ProgressView().controlSize(.small)
                    }
                    Text("Continue")
                        .font(.system(size: 18, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isBusy || status.changedFiles == 0)
        }
        .padding(22)
        .frame(minWidth: 650, idealWidth: 760)
    }
}
