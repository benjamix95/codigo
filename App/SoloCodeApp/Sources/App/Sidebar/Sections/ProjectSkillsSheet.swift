import SwiftUI
import CoderEngine

/// Sheet per skill Markdown: **globale** (`~/.solocode/skills`) o **di progetto** (`<cartella>/.solocode/skills`).
/// Le skill abilitate entrano nel *Mandatory instruction policy* (progetto prima, poi globale). Il cerchio nella lista disattiva solo quella copia (per cartella).
struct ProjectSkillsSheet: View {
    enum SkillsScope: String, CaseIterable, Identifiable {
        case global
        case project
        var id: String { rawValue }
        var title: String {
            switch self {
            case .global: return "Globale"
            case .project: return "Progetto"
            }
        }
    }

    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var providerRegistry: ProviderRegistry

    @State var skillsScope: SkillsScope = .global
    @State var skills: [SkillFile] = []
    @State var selectedSkillId: String?
    @State var editorContent = ""
    @State var newSkillName = ""
    @State var isCreating = false
    @State var aiBriefHint = ""
    @State var isGeneratingAI = false
    @State var aiErrorMessage: String?

    let projectRoot: String?

    struct SkillFile: Identifiable, Equatable {
        let id: String
        let name: String
        var content: String
        var isEnabled: Bool
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            HStack(spacing: 0) {
                skillList
                    .frame(minWidth: 200, idealWidth: 220, maxWidth: 260)
                Divider()
                skillEditor
            }
        }
        .frame(minWidth: 780, idealWidth: 840, maxWidth: 920, minHeight: 520, idealHeight: 560)
        .onAppear {
            if hasProjectSkillsTarget {
                skillsScope = .project
            } else {
                skillsScope = .global
            }
            loadSkills()
        }
        .alert("Generazione AI", isPresented: Binding(
            get: { aiErrorMessage != nil },
            set: { if !$0 { aiErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { aiErrorMessage = nil }
        } message: {
            Text(aiErrorMessage ?? "")
        }
    }

    private var headerBar: some View {
        HStack {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text("Skills")
                .font(.system(size: 14, weight: .semibold))
            if hasProjectSkillsTarget {
                Picker("", selection: $skillsScope) {
                    Text(SkillsScope.global.title).tag(SkillsScope.global)
                    Text(SkillsScope.project.title).tag(SkillsScope.project)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                .onChange(of: skillsScope) { _ in
                    isCreating = false
                    newSkillName = ""
                    aiBriefHint = ""
                    selectedSkillId = nil
                    editorContent = ""
                    loadSkills()
                }
            }
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(16)
    }

    var hasProjectSkillsTarget: Bool {
        guard let r = projectRoot?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return !r.isEmpty
    }

    /// Directory attiva in base al selettore Globale / Progetto.
    var skillsDir: String {
        switch skillsScope {
        case .global:
            return SoloCodeSkillsPolicySource.globalSkillsDirectoryPath
        case .project:
            guard let r = projectRoot?.trimmingCharacters(in: .whitespacesAndNewlines), !r.isEmpty else {
                return SoloCodeSkillsPolicySource.globalSkillsDirectoryPath
            }
            return SoloCodeSkillsPolicySource.projectSkillsDirectoryPath(forProjectRoot: r)
        }
    }

    var skillsDirectoryDisplayPath: String {
        let home = NSHomeDirectory()
        return skillsDir.replacingOccurrences(of: home, with: "~")
    }

    func sanitizeSkillName(_ raw: String) -> String {
        var name = (raw as NSString).lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasPrefix(".") { name = String(name.dropFirst()) }
        name = name.replacingOccurrences(of: "/", with: "-")
        if name.isEmpty { name = "untitled" }
        if !name.hasSuffix(".md") { name += ".md" }
        return name
    }
}
