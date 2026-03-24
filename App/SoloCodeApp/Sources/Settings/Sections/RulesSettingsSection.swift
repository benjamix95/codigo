import CoderEngine
import SwiftUI

// MARK: - Rules Settings Section

struct RulesSettingsSection: View {
    @EnvironmentObject var workspaceStore: WorkspaceStore

    // MARK: - Local State

    @State private var globalRuleDocs: [CoderRuleDocument] = []
    @State private var projectRuleDocs: [CoderRuleDocument] = []
    @State private var selectedGlobalRuleName: String = ""
    @State private var selectedProjectRuleName: String = ""
    @State private var newGlobalRuleName: String = ""
    @State private var newProjectRuleName: String = ""
    @State private var globalRuleContentDraft: String = ""
    @State private var projectRuleContentDraft: String = ""

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsSectionHeader(
                title: "Rules",
                subtitle: "Instructions and rules for all providers",
                icon: "doc.text.fill"
            )

            settingsHintBox(
                "Rules are automatically applied to ALL AI providers (API and CLI). "
                + "Use global rules for general guidance and project rules for workspace-specific constraints."
            )

            globalRulesGroup
            projectRulesGroup
        }
        .onAppear { reloadRulesFromDisk() }
    }
}

// MARK: - Sub-views

private extension RulesSettingsSection {
    var globalRulesGroup: some View {
        GroupBox("Global rules (~/.solocode/rules/global/)") {
            VStack(alignment: .leading, spacing: 10) {
                if globalRuleDocs.isEmpty {
                    Text("No global rules found. Create one to get started.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Picker("Rule", selection: $selectedGlobalRuleName) {
                        ForEach(globalRuleDocs, id: \.name) { doc in
                            Text(doc.name).tag(doc.name)
                        }
                    }
                    .onChange(of: selectedGlobalRuleName) { name in
                        globalRuleContentDraft = globalRuleDocs.first(where: { $0.name == name })?.content ?? ""
                    }
                    TextEditor(text: $globalRuleContentDraft)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
                    HStack(spacing: 8) {
                        Button("Save") { saveSelectedGlobalRule() }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                        Button("Delete", role: .destructive) { deleteSelectedGlobalRule() }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                }

                Divider()
                settingsFieldLabel("New global rule")
                HStack(spacing: 8) {
                    TextField("Name (e.g. coding-style.md)", text: $newGlobalRuleName)
                        .textFieldStyle(.roundedBorder)
                    Button("Create") { createGlobalRule() }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                }
            }.padding(4)
        }
    }

    var projectRulesGroup: some View {
        GroupBox("Project rules (.solocode/rules/project/)") {
            VStack(alignment: .leading, spacing: 10) {
                if currentProjectRootPath == nil {
                    Text("No active workspace. Open a project to manage project rules.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if projectRuleDocs.isEmpty {
                    Text("No project rules found. Create one to get started.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Picker("Rule", selection: $selectedProjectRuleName) {
                        ForEach(projectRuleDocs, id: \.name) { doc in
                            Text(doc.name).tag(doc.name)
                        }
                    }
                    .onChange(of: selectedProjectRuleName) { name in
                        projectRuleContentDraft = projectRuleDocs.first(where: { $0.name == name })?.content ?? ""
                    }
                    TextEditor(text: $projectRuleContentDraft)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
                    HStack(spacing: 8) {
                        Button("Save") { saveSelectedProjectRule() }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                        Button("Delete", role: .destructive) { deleteSelectedProjectRule() }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                }

                if currentProjectRootPath != nil {
                    Divider()
                    settingsFieldLabel("New project rule")
                    HStack(spacing: 8) {
                        TextField("Name (e.g. api-guidelines.md)", text: $newProjectRuleName)
                            .textFieldStyle(.roundedBorder)
                        Button("Create") { createProjectRule() }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                    }
                }
            }.padding(4)
        }
    }
}

// MARK: - Computed Properties

private extension RulesSettingsSection {
    var currentProjectRootPath: String? {
        if let active = workspaceStore.activeWorkspace,
           let root = active.folderPaths.first, !root.isEmpty {
            return root
        }
        return workspaceStore.workspaces.first(where: { !$0.folderPaths.isEmpty })?.folderPaths.first
    }
}

// MARK: - CRUD Actions

private extension RulesSettingsSection {
    func reloadRulesFromDisk() {
        globalRuleDocs = CoderRulesFile.loadGlobalRules()
        if selectedGlobalRuleName.isEmpty || !globalRuleDocs.contains(where: { $0.name == selectedGlobalRuleName }) {
            selectedGlobalRuleName = globalRuleDocs.first?.name ?? ""
        }
        globalRuleContentDraft = globalRuleDocs.first(where: { $0.name == selectedGlobalRuleName })?.content ?? ""

        if let root = currentProjectRootPath {
            projectRuleDocs = CoderRulesFile.loadProjectRules(workspacePath: root)
            if selectedProjectRuleName.isEmpty || !projectRuleDocs.contains(where: { $0.name == selectedProjectRuleName }) {
                selectedProjectRuleName = projectRuleDocs.first?.name ?? ""
            }
            projectRuleContentDraft = projectRuleDocs.first(where: { $0.name == selectedProjectRuleName })?.content ?? ""
        } else {
            projectRuleDocs = []
            selectedProjectRuleName = ""
            projectRuleContentDraft = ""
        }
    }

    func createGlobalRule() {
        let base = newGlobalRuleName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return }
        CoderRulesFile.saveGlobalRule(name: base, content: "# \(base.replacingOccurrences(of: ".md", with: ""))\n")
        newGlobalRuleName = ""
        reloadRulesFromDisk()
        if let created = globalRuleDocs.last?.name {
            selectedGlobalRuleName = created
            globalRuleContentDraft = globalRuleDocs.first(where: { $0.name == created })?.content ?? ""
        }
    }

    func saveSelectedGlobalRule() {
        guard !selectedGlobalRuleName.isEmpty else { return }
        CoderRulesFile.saveGlobalRule(name: selectedGlobalRuleName, content: globalRuleContentDraft)
        reloadRulesFromDisk()
    }

    func deleteSelectedGlobalRule() {
        guard !selectedGlobalRuleName.isEmpty else { return }
        CoderRulesFile.deleteGlobalRule(name: selectedGlobalRuleName)
        reloadRulesFromDisk()
    }

    func createProjectRule() {
        guard let root = currentProjectRootPath else { return }
        let base = newProjectRuleName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return }
        CoderRulesFile.saveProjectRule(
            name: base,
            content: "# \(base.replacingOccurrences(of: ".md", with: ""))\n",
            workspacePath: root
        )
        newProjectRuleName = ""
        reloadRulesFromDisk()
        if let created = projectRuleDocs.last?.name {
            selectedProjectRuleName = created
            projectRuleContentDraft = projectRuleDocs.first(where: { $0.name == created })?.content ?? ""
        }
    }

    func saveSelectedProjectRule() {
        guard let root = currentProjectRootPath, !selectedProjectRuleName.isEmpty else { return }
        CoderRulesFile.saveProjectRule(name: selectedProjectRuleName, content: projectRuleContentDraft, workspacePath: root)
        reloadRulesFromDisk()
    }

    func deleteSelectedProjectRule() {
        guard let root = currentProjectRootPath, !selectedProjectRuleName.isEmpty else { return }
        CoderRulesFile.deleteProjectRule(name: selectedProjectRuleName, workspacePath: root)
        reloadRulesFromDisk()
    }
}
