import SwiftUI

extension SettingsView {
    var rulesSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader(title: "Rules", subtitle: "Instructions and rules for all providers", icon: "doc.text.fill")

            hintBox("Rules are automatically applied to ALL AI providers (API and CLI). Use global rules for general guidance and project rules for workspace-specific constraints.")

            GroupBox("Global rules (~/.codigo/rules/global/)") {
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
                        .onChange(of: selectedGlobalRuleName) { _, name in
                            globalRuleContentDraft = globalRuleDocs.first(where: { $0.name == name })?.content ?? ""
                        }
                        TextEditor(text: $globalRuleContentDraft)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(height: 140)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
                        HStack(spacing: 8) {
                            Button("Save") { saveSelectedGlobalRule() }.buttonStyle(.borderedProminent).controlSize(.small)
                            Button("Delete", role: .destructive) { deleteSelectedGlobalRule() }.buttonStyle(.bordered).controlSize(.small)
                        }
                    }

                    Divider()
                    fieldLabel("New global rule")
                    HStack(spacing: 8) {
                        TextField("Name (e.g. coding-style.md)", text: $newGlobalRuleName).textFieldStyle(.roundedBorder)
                        Button("Create") { createGlobalRule() }.buttonStyle(.borderedProminent).controlSize(.small)
                    }
                }.padding(4)
            }

            GroupBox("Project rules (.codigo/rules/project/)") {
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
                        .onChange(of: selectedProjectRuleName) { _, name in
                            projectRuleContentDraft = projectRuleDocs.first(where: { $0.name == name })?.content ?? ""
                        }
                        TextEditor(text: $projectRuleContentDraft)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(height: 140)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
                        HStack(spacing: 8) {
                            Button("Save") { saveSelectedProjectRule() }.buttonStyle(.borderedProminent).controlSize(.small)
                            Button("Delete", role: .destructive) { deleteSelectedProjectRule() }.buttonStyle(.bordered).controlSize(.small)
                        }
                    }

                    if currentProjectRootPath != nil {
                        Divider()
                        fieldLabel("New project rule")
                        HStack(spacing: 8) {
                            TextField("Name (e.g. api-guidelines.md)", text: $newProjectRuleName).textFieldStyle(.roundedBorder)
                            Button("Create") { createProjectRule() }.buttonStyle(.borderedProminent).controlSize(.small)
                        }
                    }
                }.padding(4)
            }
        }
    }
}
