import AppKit
import CoderEngine
import SwiftUI

// MARK: - Settings View (Thin Shell)

/// SettingsView is a thin navigation shell. Each section is a standalone View
/// that owns its own @AppStorage and onChange handlers, avoiding body-scope
/// re-renders when unrelated settings change.
struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var workspaceStore: WorkspaceStore
    @EnvironmentObject var providerRegistry: ProviderRegistry
    @EnvironmentObject var executionController: ExecutionController
    @EnvironmentObject var providerUsageStore: ProviderUsageStore
    @EnvironmentObject var appUpdateCenter: AppUpdateCenter
    @State var selectedSection: SettingsSection = .apiKeys
    @StateObject private var syncCoordinator = SettingsSyncCoordinator()

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedSection) {
                Section("Provider AI") {
                    ForEach(SettingsSection.providerAI) { section in
                        Label(section.rawValue, systemImage: section.icon).tag(section)
                    }
                }
                Section("Tools") {
                    ForEach(SettingsSection.tools) { section in
                        Label(section.rawValue, systemImage: section.icon).tag(section)
                    }
                }
                Section("General") {
                    ForEach(SettingsSection.general) { section in
                        Label(section.rawValue, systemImage: section.icon).tag(section)
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 180)
        } detail: {
            ScrollView {
                detailContent
                    .frame(maxWidth: 560, alignment: .leading)
                    .padding(24)
            }
        }
        .frame(width: 760, height: 520)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .environmentObject(syncCoordinator)
        .onAppear {
            syncCoordinator.bind(
                registry: providerRegistry,
                execution: executionController,
                workspace: workspaceStore
            )
            FontPreferences.registerBundledFonts()
            syncCoordinator.syncAll()
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedSection {
        case .custom:
            CustomSettingsSection()
        case .apiKeys:
            APIKeysSettingsSection()
        case .cliTools:
            CLIToolsSettingsSection()
        case .mcp:
            MCPSettingsSection()
        case .skillsPlugins:
            SkillsPluginsSection()
        case .rules:
            RulesSettingsSection()
        case .codebaseIndex:
            CodebaseIndexSettingsSection()
        case .behavior:
            BehaviorSettingsSection()
        case .appearance:
            AppearanceSettingsSection()
        }
    }
}
