import SwiftUI

extension ProjectSkillsSheet {

    var skillEditor: some View {
        Group {
            if isCreating {
                newSkillEditor
            } else if let skill = skills.first(where: { $0.id == selectedSkillId }) {
                existingSkillEditor(skill)
            } else {
                emptyEditor
            }
        }
    }

    private var newSkillEditor: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Nome file")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                        TextField("mia-skill.md", text: $newSkillName)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                    }
                    .frame(maxWidth: 260)

                    Spacer(minLength: 8)

                    Button {
                        Task { await generateSkillWithAI() }
                    } label: {
                        if isGeneratingAI {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Genera con AI", systemImage: "sparkles")
                                .font(.system(size: 11, weight: .semibold))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(isGeneratingAI || resolveAIProvider() == nil)

                    Button("Salva skill") { commitNewSkillFromDraft() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .disabled(
                            newSkillName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || isGeneratingAI
                        )
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Cosa deve fare (opzionale — usato solo per «Genera con AI»)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                    TextField(
                        "Es.: revisione accessibilità SwiftUI, convenzioni commit, …",
                        text: $aiBriefHint,
                        axis: .vertical
                    )
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                    .font(.system(size: 11))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            TextEditor(text: $editorContent)
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if resolveAIProvider() == nil {
                Text("Seleziona e configura un provider nelle impostazioni chat per usare «Genera con AI».")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignSystem.Colors.textQuaternary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
        }
    }

    private func existingSkillEditor(_ skill: SkillFile) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(skill.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                Spacer()
                Button {
                    Task { await generateSkillWithAIReplacing(skill: skill) }
                } label: {
                    if isGeneratingAI {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Rigenera con AI", systemImage: "sparkles")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isGeneratingAI || resolveAIProvider() == nil)
                Button("Save") { saveSkill() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            VStack(alignment: .leading, spacing: 4) {
                Text("Istruzioni per la rigenerazione (opzionale)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                TextField("Es.: aggiungi checklist sicurezza…", text: $aiBriefHint, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...3)
                    .font(.system(size: 11))
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            Divider()

            TextEditor(text: $editorContent)
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var emptyEditor: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 32))
                .foregroundStyle(DesignSystem.Colors.textQuaternary)
            Text("Nessuna skill selezionata")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.textSecondary)
            Button("Nuova skill…", action: beginNewSkillDraft)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
