import SwiftUI

extension CodeReviewPanelView {
    // MARK: - Commands Tab

    func commandsTab(_ m: CodeReviewMetrics) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                againstCommitCard
                slashCommandsCard

                if !m.workers.isEmpty {
                    workersCard(m.workers)
                }

                if !m.cards.isEmpty {
                    liveStatusCard(m.cards)
                }
            }
            .padding(12)
        }
    }

    var againstCommitCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(accent)
                Text("AGAINST COMMIT")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.8)
            }

            Text("Review changes against a specific commit reference")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                TextField("HEAD~1, abc123, main..feature", text: $againstCommitRef)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(maxWidth: .infinity)

                Button { runAgainstCommitReview() } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(accent))
                }
                .buttonStyle(.plain)
                .disabled(!isValidGitRef(againstCommitRef) || isTaskRunning)
            }

            HStack(spacing: 8) {
                Toggle(isOn: Binding(get: { autofixEnabled }, set: { setAutofixEnabled($0) })) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 9))
                        Text("Autofix")
                            .font(.system(size: 10.5, weight: .medium))
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .disabled(isTaskRunning)
                Spacer()
                if autofixEnabled {
                    Text("max \(codeReviewMaxRounds) rounds")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.quaternary)
                }
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

    // MARK: - Slash Commands Card

    var slashCommandsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "terminal")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(accent)
                Text("QUICK COMMANDS")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.8)
            }

            ForEach(slashCommands, id: \.id) { cmd in
                Button {
                    if coderMode != .codeReviewMultiSwarm {
                        onSelectMode(.codeReviewMultiSwarm)
                        Task { @MainActor in
                            onRunSlashCommand(cmd.prompt)
                        }
                    } else {
                        onRunSlashCommand(cmd.prompt)
                    }
                } label: {
                    HStack(spacing: 0) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(accent.opacity(0.6))
                            .frame(width: 2.5)
                            .padding(.vertical, 3)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(cmd.slash)
                                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                .foregroundStyle(accent)
                            Text(cmd.label)
                                .font(.system(size: 9.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .padding(.leading, 8)
                        .padding(.vertical, 5)

                        Spacer(minLength: 4)

                        Image(systemName: "arrow.right")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.quaternary)
                            .padding(.trailing, 8)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.35))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(DesignSystem.Colors.border.opacity(0.3), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isTaskRunning)
            }
        }
    }

    func statusAccent(_ s: SwarmCardStatus) -> Color {
        switch s {
        case .running: return accent
        case .completed: return DesignSystem.Colors.success
        case .failed: return DesignSystem.Colors.error
        case .idle: return .secondary
        }
    }

    func reviewCardName(_ swarmId: String) -> String {
        let id = swarmId.trimmingCharacters(in: .whitespacesAndNewlines)
        if id.lowercased().hasPrefix("review-") {
            let suffix = String(id.dropFirst("review-".count))
            if !suffix.isEmpty, suffix.allSatisfy(\.isNumber) {
                return "Review \(suffix)"
            }
        }
        if let dash = id.range(of: "-", options: .backwards) {
            let suffix = id[dash.upperBound...]
            if suffix.count >= 8, suffix.allSatisfy({ $0.isHexDigit }) {
                return String(id[..<dash.lowerBound]).capitalized
            }
        }
        return id.capitalized
    }
}
