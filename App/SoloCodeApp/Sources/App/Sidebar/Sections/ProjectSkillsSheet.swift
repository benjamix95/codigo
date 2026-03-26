import SwiftUI
import CoderEngine

/// Sheet for managing project-level skills (Markdown in ~/.solocode/skills/).
struct ProjectSkillsSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var providerRegistry: ProviderRegistry

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
        .onAppear { loadSkills() }
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
            Text("Project Skills")
                .font(.system(size: 14, weight: .semibold))
            Spacer()
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(16)
    }

    /// Percorso ~/.solocode/skills (skill globali app).
    var skillsDir: String {
        (NSHomeDirectory() as NSString).appendingPathComponent(".solocode/skills")
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
