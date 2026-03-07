import CoderEngine
import SwiftUI

/// Settings tab for the Code Review Panel: pipeline config, backends,
/// custom instructions, and custom commands editor.
struct ReviewPanelSettingsTab: View {
    @ObservedObject var store: CodeReviewPanelStore
    @State private var showCustomCommands = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 16) {
                pipelineSection
                backendsSection
                instructionsSection
                customCommandsSection
                dangerZone
            }
            .padding(12)
        }
        .sheet(isPresented: $showCustomCommands) {
            ReviewPanelCustomCommands(store: store)
        }
    }

    // MARK: - Pipeline

    private var pipelineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("PIPELINE", icon: "slider.horizontal.3")

            settingsRow("Max Workers") {
                Stepper(
                    value: Binding(
                        get: { store.settings.maxWorkers },
                        set: { store.updatePipelineSettings(maxWorkers: $0) }
                    ),
                    in: 1...10
                ) {
                    Text("\(store.settings.maxWorkers)")
                        .font(.system(size: 10, weight: .semibold,
                                      design: .monospaced))
                        .foregroundStyle(.primary)
                }
                .controlSize(.mini)
            }

            settingsRow("Max Rounds") {
                Stepper(
                    value: Binding(
                        get: { store.settings.maxRounds },
                        set: { store.updatePipelineSettings(maxRounds: $0) }
                    ),
                    in: 1...10
                ) {
                    Text("\(store.settings.maxRounds)")
                        .font(.system(size: 10, weight: .semibold,
                                      design: .monospaced))
                        .foregroundStyle(.primary)
                }
                .controlSize(.mini)
            }

            settingsRow("Analysis Only") {
                Toggle(
                    "",
                    isOn: Binding(
                        get: { store.settings.analysisOnly },
                        set: { store.updatePipelineSettings(analysisOnly: $0) }
                    )
                )
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
            }
        }
    }

    // MARK: - Backends

    private var backendsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("BACKENDS", icon: "cpu")

            settingsRow("Analysis") {
                Text(store.settings.analysisBackend)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            settingsRow("Execution") {
                Text(store.settings.executionBackend)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Instructions

    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("CUSTOM INSTRUCTIONS", icon: "doc.text")

            TextEditor(
                text: Binding(
                    get: { store.settings.customInstructions },
                    set: { store.updateCustomInstructions($0) }
                )
            )
            .font(.system(size: 10, design: .monospaced))
            .frame(minHeight: 60, maxHeight: 120)
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.4))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        DesignSystem.Colors.border.opacity(0.3),
                        lineWidth: 0.5
                    )
            )

            Text("Extra instructions appended to every review prompt.")
                .font(.system(size: 9))
                .foregroundStyle(.quaternary)
        }
    }

    // MARK: - Custom Commands

    private var customCommandsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionHeader("CUSTOM COMMANDS", icon: "terminal")
                Spacer()
                Button { showCustomCommands = true } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "pencil")
                            .font(.system(size: 8))
                        Text("Edit")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundStyle(store.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        store.accent.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
            }

            if store.settings.customCommands.isEmpty {
                Text("No custom commands yet. Tap Edit to add.")
                    .font(.system(size: 10))
                    .foregroundStyle(.quaternary)
                    .padding(.vertical, 4)
            } else {
                commandsList
            }
        }
    }

    private var commandsList: some View {
        VStack(spacing: 3) {
            ForEach(store.settings.customCommands) { cmd in
                HStack(spacing: 6) {
                    Image(systemName: cmd.icon)
                        .font(.system(size: 9))
                        .foregroundStyle(store.accent)
                        .frame(width: 14)
                    Text(cmd.displayCommand)
                        .font(.system(size: 10, weight: .medium,
                                      design: .monospaced))
                        .foregroundStyle(.primary.opacity(0.9))
                    Text(cmd.name)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor)
                            .opacity(0.3))
                )
            }
        }
    }

    // MARK: - Danger Zone

    private var dangerZone: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("RESET", icon: "arrow.counterclockwise")

            Button {
                store.resetSettingsToDefaults()
            } label: {
                Text("Reset to Defaults")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.error)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        DesignSystem.Colors.error.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(store.accent)
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.tertiary)
                .tracking(0.8)
        }
    }

    private func settingsRow<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.primary.opacity(0.85))
            Spacer()
            content()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        )
    }
}
