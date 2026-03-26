import CoderEngine
import SwiftUI

extension ProjectSkillsSheet {

    func beginNewSkillDraft() {
        isCreating = true
        selectedSkillId = nil
        newSkillName = "mia-skill.md"
        aiBriefHint = ""
        editorContent = """
        # Mia skill

        ## Quando usarla
        - …

        ## Passi
        1. …

        """
    }

    func cancelDraft() {
        isCreating = false
        newSkillName = ""
        aiBriefHint = ""
        editorContent = ""
        loadSkills()
    }

    func commitNewSkillFromDraft() {
        let name = sanitizeSkillName(newSkillName)
        let path = "\(skillsDir)/\(name)"
        try? editorContent.write(toFile: path, atomically: true, encoding: .utf8)
        isCreating = false
        newSkillName = ""
        aiBriefHint = ""
        loadSkills()
        selectedSkillId = name
        editorContent = (try? String(contentsOfFile: path, encoding: .utf8)) ?? editorContent
    }

    func resolveAIProvider() -> (any LLMProvider)? {
        if let selected = providerRegistry.selectedProvider, selected.isAuthenticated() {
            return selected
        }
        if let codex = providerRegistry.provider(for: "codex-cli"), codex.isAuthenticated() {
            return codex
        }
        if let claude = providerRegistry.provider(for: "claude-cli"), claude.isAuthenticated() {
            return claude
        }
        return nil
    }

    @MainActor
    func generateSkillWithAI() async {
        guard let provider = resolveAIProvider() else {
            aiErrorMessage = "Nessun provider AI disponibile. Apri Impostazioni e configura un account."
            return
        }
        let stem = newSkillName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stem.isEmpty else { return }
        isGeneratingAI = true
        defer { isGeneratingAI = false }
        do {
            let md = try await SkillMarkdownAIService.generate(
                skillFileNameStem: stem,
                userRequest: aiBriefHint,
                provider: provider,
                projectRoot: projectRoot
            )
            editorContent = md
        } catch {
            aiErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    func generateSkillWithAIReplacing(skill: SkillFile) async {
        guard let provider = resolveAIProvider() else {
            aiErrorMessage = "Nessun provider AI disponibile."
            return
        }
        isGeneratingAI = true
        defer { isGeneratingAI = false }
        do {
            let md = try await SkillMarkdownAIService.generate(
                skillFileNameStem: skill.name,
                userRequest: aiBriefHint.isEmpty
                    ? "Improve and clarify this skill; keep Markdown structure.\n\n\(editorContent)"
                    : aiBriefHint,
                provider: provider,
                projectRoot: projectRoot
            )
            editorContent = md
        } catch {
            aiErrorMessage = error.localizedDescription
        }
    }

    func loadSkills() {
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
        if !isCreating {
            if selectedSkillId == nil, let first = skills.first {
                selectedSkillId = first.id
                editorContent = first.content
            } else if let id = selectedSkillId, let s = skills.first(where: { $0.id == id }) {
                editorContent = s.content
            }
        }
    }

    func saveSkill() {
        guard let id = selectedSkillId else { return }
        let safeName = sanitizeSkillName(id)
        let path = "\(skillsDir)/\(safeName)"
        try? editorContent.write(toFile: path, atomically: true, encoding: .utf8)
        loadSkills()
    }

    func deleteSkill(_ skill: SkillFile) {
        let safeName = sanitizeSkillName(skill.name)
        try? FileManager.default.removeItem(atPath: "\(skillsDir)/\(safeName)")
        try? FileManager.default.removeItem(atPath: "\(skillsDir)/.\(safeName).disabled")
        if selectedSkillId == skill.id { selectedSkillId = nil; editorContent = "" }
        loadSkills()
    }

    func toggleSkill(_ skill: SkillFile) {
        let safeName = sanitizeSkillName(skill.name)
        let marker = "\(skillsDir)/.\(safeName).disabled"
        if skill.isEnabled {
            try? "".write(toFile: marker, atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(atPath: marker)
        }
        loadSkills()
    }
}
