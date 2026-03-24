import CoderEngine
import SwiftUI

/// Sheet for managing global and project-level rules.
/// Uses `CoderRulesFile` for IO — same backend as Settings > Rules.
struct SidebarRulesSheet: View {
    @Environment(\.dismiss) var dismiss
    let projectRoot: String?

    enum Scope: String, CaseIterable, Identifiable {
        case global = "Global"
        case project = "Project"
        var id: String { rawValue }
    }

    @State private var scope: Scope = .project
    @State private var rules: [CoderRuleDocument] = []
    @State private var selectedRuleName = ""
    @State private var editorContent = ""
    @State private var newRuleName = ""
    @State private var isCreating = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                ruleList.frame(width: 220)
                Divider()
                ruleEditor
            }
        }
        .frame(width: 720, height: 480)
        .onAppear { loadRules() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "list.bullet.clipboard")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text("Rules")
                .font(.system(size: 14, weight: .semibold))

            Spacer()

            Picker("", selection: $scope) {
                ForEach(Scope.allCases) { s in
                    Text(s.rawValue).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
            .onChange(of: scope) { _ in loadRules() }

            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(16)
    }

    // MARK: - Rule List

    private var ruleList: some View {
        VStack(alignment: .leading, spacing: 0) {
            scopeLabel

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(rules, id: \.name) { rule in
                        ruleRow(rule)
                    }
                }
                .padding(8)
            }

            Divider()
            newRuleBar
        }
    }

    private var scopeLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: scope == .global ? "globe" : "folder")
                .font(.system(size: 10))
                .foregroundStyle(DesignSystem.Colors.textTertiary)
            Text(scope == .global
                 ? "~/.solocode/rules/global/"
                 : ".solocode/rules/project/")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(DesignSystem.Colors.textTertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func ruleRow(_ rule: CoderRuleDocument) -> some View {
        let isSelected = selectedRuleName == rule.name
        return Button {
            selectedRuleName = rule.name
            editorContent = rule.content
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "doc.text")
                    .font(.system(size: 10))
                    .foregroundStyle(isSelected ? Color.accentColor : DesignSystem.Colors.textQuaternary)
                Text(rule.name)
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
            Button(role: .destructive) { deleteRule(rule) } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var newRuleBar: some View {
        HStack(spacing: 6) {
            if isCreating {
                TextField("rule-name.md", text: $newRuleName)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11))
                    .onSubmit { createRule() }
                Button(action: createRule) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .disabled(newRuleName.trimmingCharacters(in: .whitespaces).isEmpty)
                Button(action: { isCreating = false; newRuleName = "" }) {
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(DesignSystem.Colors.textQuaternary)
                }
                .buttonStyle(.plain)
            } else {
                Button { isCreating = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 11))
                        Text("New Rule")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
    }

    // MARK: - Editor

    private var ruleEditor: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !selectedRuleName.isEmpty {
                HStack {
                    Text(selectedRuleName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                    Spacer()
                    Button("Save") { saveRule() }
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
                emptyEditor
            }
        }
    }

    private var emptyEditor: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.system(size: 28))
                .foregroundStyle(DesignSystem.Colors.textQuaternary)
            Text("Select a rule to edit")
                .font(.system(size: 12))
                .foregroundStyle(DesignSystem.Colors.textTertiary)
            if scope == .project && projectRoot == nil {
                Text("No active project for project rules.")
                    .font(.system(size: 11))
                    .foregroundStyle(DesignSystem.Colors.textQuaternary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - IO

    private func loadRules() {
        switch scope {
        case .global:
            CoderRulesFile.ensureGlobalRulesDir()
            rules = CoderRulesFile.loadGlobalRules()
        case .project:
            guard let root = projectRoot else { rules = []; return }
            CoderRulesFile.ensureProjectRulesDir(workspacePath: root)
            rules = CoderRulesFile.loadProjectRules(workspacePath: root)
        }
        if !rules.contains(where: { $0.name == selectedRuleName }) {
            selectedRuleName = rules.first?.name ?? ""
            editorContent = rules.first?.content ?? ""
        }
    }

    private func createRule() {
        let name = newRuleName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let template = "# \(name.replacingOccurrences(of: ".md", with: ""))\n\n"
        switch scope {
        case .global:
            CoderRulesFile.saveGlobalRule(name: name, content: template)
        case .project:
            guard let root = projectRoot else { return }
            CoderRulesFile.saveProjectRule(name: name, content: template, workspacePath: root)
        }
        newRuleName = ""
        isCreating = false
        loadRules()
        let sanitized = name.hasSuffix(".md") ? name : "\(name).md"
        selectedRuleName = sanitized
        editorContent = template
    }

    private func saveRule() {
        guard !selectedRuleName.isEmpty else { return }
        switch scope {
        case .global:
            CoderRulesFile.saveGlobalRule(name: selectedRuleName, content: editorContent)
        case .project:
            guard let root = projectRoot else { return }
            CoderRulesFile.saveProjectRule(
                name: selectedRuleName, content: editorContent, workspacePath: root)
        }
        loadRules()
    }

    private func deleteRule(_ rule: CoderRuleDocument) {
        switch scope {
        case .global:
            CoderRulesFile.deleteGlobalRule(name: rule.name)
        case .project:
            guard let root = projectRoot else { return }
            CoderRulesFile.deleteProjectRule(name: rule.name, workspacePath: root)
        }
        if selectedRuleName == rule.name {
            selectedRuleName = ""
            editorContent = ""
        }
        loadRules()
    }
}
