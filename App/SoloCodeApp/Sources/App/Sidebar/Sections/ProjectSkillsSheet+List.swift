import SwiftUI

extension ProjectSkillsSheet {

    var skillList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: skillsScope == .global ? "globe" : "folder")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                Text(skillsDirectoryDisplayPath)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                    .lineLimit(2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            if skills.isEmpty && !isCreating {
                VStack(spacing: 10) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 26))
                        .foregroundStyle(DesignSystem.Colors.textQuaternary)
                    Text("Nessuna skill ancora")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                    Text("Crea una bozza: avrai subito l’editor e potrai chiedere all’AI di scriverla.")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignSystem.Colors.textQuaternary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                    Button(action: beginNewSkillDraft) {
                        Label("Nuova skill", systemImage: "square.and.pencil")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if isCreating {
                            draftListRow
                        }
                        ForEach(skills) { skill in
                            skillRow(skill)
                        }
                    }
                    .padding(8)
                }
            }

            Divider()

            HStack(spacing: 8) {
                if isCreating {
                    Text("Bozza")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                    Spacer(minLength: 0)
                    Button("Annulla bozza") { cancelDraft() }
                        .font(.system(size: 11))
                } else {
                    Button(action: beginNewSkillDraft) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 11))
                            Text("Nuova skill")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                }
            }
            .padding(10)
        }
    }

    private var draftListRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "pencil.and.outline")
                .font(.system(size: 10))
                .foregroundStyle(Color.accentColor)
            Text(newSkillName.isEmpty ? "Bozza nuova skill" : newSkillName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.accentColor.opacity(0.12))
        )
    }

    func skillRow(_ skill: SkillFile) -> some View {
        let isSelected = !isCreating && selectedSkillId == skill.id
        return Button {
            isCreating = false
            selectedSkillId = skill.id
            editorContent = skill.content
            aiBriefHint = ""
        } label: {
            HStack(spacing: 6) {
                Image(systemName: skill.isEnabled ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 10))
                    .foregroundStyle(skill.isEnabled ? Color.accentColor : DesignSystem.Colors.textQuaternary)
                    .onTapGesture { toggleSkill(skill) }

                Text(skill.name)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) { deleteSkill(skill) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
