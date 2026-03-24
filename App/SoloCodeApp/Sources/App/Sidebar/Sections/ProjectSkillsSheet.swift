import SwiftUI

/// Sheet for managing project-level skills (rules applied to all LLM providers).
/// Skills are stored as `.md` files in `.solocode/skills/` within the project root.
struct ProjectSkillsSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var skills: [SkillFile] = []
    @State private var selectedSkillId: String?
    @State private var editorContent = ""
    @State private var newSkillName = ""
    @State private var isCreating = false
    let projectRoot: String?

    struct SkillFile: Identifiable, Equatable {
        let id: String
        let name: String
        var content: String
        var isEnabled: Bool
    }

    /// Skills are global — stored in ~/.solocode/skills/
    private var skillsDir: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".solocode/skills")
    }

    /// Sanitize skill file name to prevent path traversal.
    private func sanitizeSkillName(_ raw: String) -> String {
        var name = (raw as NSString).lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Remove leading dots to prevent hidden file creation
        while name.hasPrefix(".") { name = String(name.dropFirst()) }
        name = name.replacingOccurrences(of: "/", with: "-")
        if name.isEmpty { name = "untitled" }
        if !name.hasSuffix(".md") { name += ".md" }
        return name
    }

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ──────────────────────────────────
            HStack {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text("Project Skills")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .padding(16)

            Divider()

            HStack(spacing: 0) {
                skillList
                    .frame(width: 200)
                Divider()
                skillEditor
            }
        }
        .frame(width: 680, height: 460)
        .onAppear { loadSkills() }
    }

    // MARK: - Skill List

    private var skillList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if skills.isEmpty && !isCreating {
                VStack(spacing: 8) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 24))
                        .foregroundStyle(DesignSystem.Colors.textQuaternary)
                    Text("No skills yet")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                    Button { isCreating = true } label: {
                        Label("Create First Skill", systemImage: "plus.circle.fill")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(skills) { skill in
                            skillRow(skill)
                        }
                    }
                    .padding(8)
                }
            }

            Divider()

            // New skill
            HStack(spacing: 6) {
                if isCreating {
                    TextField("skill-name.md", text: $newSkillName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                        .onSubmit { createSkill() }
                    Button(action: createSkill) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(newSkillName.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button(action: { isCreating = false; newSkillName = "" }) {
                        Image(systemName: "xmark.circle")
                            .foregroundStyle(DesignSystem.Colors.textQuaternary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button { isCreating = true } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 11))
                            Text("New Skill")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
        }
    }

    private func skillRow(_ skill: SkillFile) -> some View {
        let isSelected = selectedSkillId == skill.id
        return Button {
            selectedSkillId = skill.id
            editorContent = skill.content
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

    // MARK: - Editor

    private var skillEditor: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let skill = skills.first(where: { $0.id == selectedSkillId }) {
                HStack {
                    Text(skill.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                    Spacer()
                    Button("Save") { saveSkill() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

                Divider()

                TextEditor(text: $editorContent)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 28))
                        .foregroundStyle(DesignSystem.Colors.textQuaternary)
                    Text("Select a skill to edit")
                        .font(.system(size: 12))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var noProjectState: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 32))
                .foregroundStyle(DesignSystem.Colors.textQuaternary)
            Text("No active project")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.textSecondary)
            Text("Open a project to create and manage skills.")
                .font(.system(size: 11))
                .foregroundStyle(DesignSystem.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - File Operations

    private func loadSkills() {
        let dir = skillsDir
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir) {
            try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        guard let files = try? fm.contentsOfDirectory(atPath: dir) else { return }
        skills = files
            .filter { $0.hasSuffix(".md") }
            .sorted()
            .map { name in
                let path = "\(dir)/\(name)"
                let content = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
                let disabledMarker = "\(dir)/.\(name).disabled"
                let isEnabled = !fm.fileExists(atPath: disabledMarker)
                return SkillFile(id: name, name: name, content: content, isEnabled: isEnabled)
            }
        if selectedSkillId == nil, let first = skills.first {
            selectedSkillId = first.id
            editorContent = first.content
        }
    }

    private func createSkill() {
        let dir = skillsDir
        let name = sanitizeSkillName(newSkillName)
        let path = "\(dir)/\(name)"
        let template = "# \(name.replacingOccurrences(of: ".md", with: ""))\n\nDescribe this skill...\n"
        try? template.write(toFile: path, atomically: true, encoding: .utf8)
        newSkillName = ""
        isCreating = false
        loadSkills()
        selectedSkillId = name
        editorContent = template
    }

    private func saveSkill() {
        guard let id = selectedSkillId else { return }
        let dir = skillsDir
        let safeName = sanitizeSkillName(id)
        let path = "\(dir)/\(safeName)"
        try? editorContent.write(toFile: path, atomically: true, encoding: .utf8)
        loadSkills()
    }

    private func deleteSkill(_ skill: SkillFile) {
        let dir = skillsDir
        let safeName = sanitizeSkillName(skill.name)
        try? FileManager.default.removeItem(atPath: "\(dir)/\(safeName)")
        try? FileManager.default.removeItem(atPath: "\(dir)/.\(safeName).disabled")
        if selectedSkillId == skill.id { selectedSkillId = nil; editorContent = "" }
        loadSkills()
    }

    private func toggleSkill(_ skill: SkillFile) {
        let dir = skillsDir
        let safeName = sanitizeSkillName(skill.name)
        let marker = "\(dir)/.\(safeName).disabled"
        if skill.isEnabled {
            try? "".write(toFile: marker, atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(atPath: marker)
        }
        loadSkills()
    }
}
