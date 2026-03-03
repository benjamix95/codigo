import SwiftUI

extension CodeReviewPanelView {
    var configTab: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                if isTaskRunning {
                    Text("Configuration changes apply to the next review run.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                configCard(title: "Max Workers", icon: "person.3.fill") {
                    HStack {
                        Text("Concurrent workers")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Stepper(value: $codeReviewPartitions, in: 1...12) {
                            Text("\(codeReviewPartitions)")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(accent)
                        }
                        .fixedSize()
                    }
                    Text("The analysis LLM decides how many to spawn (up to this limit)")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.quaternary)
                }

                configCard(title: "Max Rounds", icon: "arrow.triangle.2.circlepath") {
                    HStack {
                        Text("Autofix rounds")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Stepper(value: $codeReviewMaxRounds, in: 1...10) {
                            Text("\(codeReviewMaxRounds)")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(accent)
                        }
                        .fixedSize()
                    }
                }

                configCard(title: "Mode", icon: "eye") {
                    Toggle(isOn: $codeReviewAnalysisOnly) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Analysis Only")
                                .font(.system(size: 10.5, weight: .medium))
                            Text("Report findings without applying fixes")
                                .font(.system(size: 9.5))
                                .foregroundStyle(.quaternary)
                        }
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                }

                configCard(title: "Analysis Backend", icon: "cpu") {
                    Picker("", selection: $codeReviewAnalysisBackend) {
                        Text("Auto (same as Agent)").tag("auto")
                        Text("Codex CLI").tag("codex-cli")
                        Text("Claude Code").tag("claude-cli")
                        Text("Anthropic API").tag("anthropic-api")
                        Text("OpenAI API").tag("openai-api")
                        Text("Google API").tag("google-api")
                        Text("OpenRouter API").tag("openrouter-api")
                    }
                    .pickerStyle(.menu)
                    .fixedSize()
                }

                if !codeReviewAnalysisOnly {
                    configCard(title: "Execution Backend", icon: "hammer") {
                        Picker("", selection: $codeReviewExecutionBackend) {
                            Text("Auto (same as Agent)").tag("auto")
                            Text("Codex CLI").tag("codex-cli")
                            Text("Claude Code").tag("claude-cli")
                            Text("Anthropic API").tag("anthropic-api")
                            Text("OpenAI API").tag("openai-api")
                            Text("Google API").tag("google-api")
                            Text("OpenRouter API").tag("openrouter-api")
                        }
                        .pickerStyle(.menu)
                        .fixedSize()
                    }
                }
            }
            .padding(12)
            .disabled(isTaskRunning)
            .opacity(isTaskRunning ? 0.78 : 1)
        }
    }

    func configCard<C: View>(title: String, icon: String, @ViewBuilder content: () -> C) -> some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(accent.opacity(0.5))
                .frame(width: 2.5)
                .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: icon)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(accent)
                    Text(title.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .tracking(0.6)
                }
                content()
            }
            .padding(.leading, 8)
            .padding(.vertical, 8)
            .padding(.trailing, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(DesignSystem.Colors.border.opacity(0.4), lineWidth: 0.5)
        )
    }
}
