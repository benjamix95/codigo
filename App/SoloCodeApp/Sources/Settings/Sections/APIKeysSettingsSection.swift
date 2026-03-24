import SwiftUI
import CoderEngine

// MARK: - API Keys Settings Section (Standalone)

struct APIKeysSettingsSection: View {
    @State var providerKeys = SettingsProviderKeys()

    @EnvironmentObject var syncCoordinator: SettingsSyncCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            settingsSectionHeader(title: "API Keys", subtitle: "API keys for AI providers", icon: "key.fill")

            openaiGroup
            anthropicGroup
            geminiGroup
            minimaxGroup
            openRouterGroup
            grokGroup
            webSearchGroup

            settingsHintBox("Models are selected directly from the chat bar, not from settings.")
        }
        .onChange(of: providerKeys.openaiApiKey) { _ in syncCoordinator.syncOpenAI() }
        .onChange(of: providerKeys.anthropicApiKey) { _ in syncCoordinator.syncAnthropic() }
        .onChange(of: providerKeys.anthropicAdminApiKey) { _ in syncCoordinator.syncAnthropic() }
        .onChange(of: providerKeys.googleApiKey) { _ in syncCoordinator.syncGoogle() }
        .onChange(of: providerKeys.minimaxApiKey) { _ in syncCoordinator.syncMiniMax() }
        .onChange(of: providerKeys.openrouterApiKey) { _ in syncCoordinator.syncOpenRouter() }
        .onChange(of: providerKeys.grokApiKey) { _ in syncCoordinator.syncGrok() }
        .onChange(of: providerKeys.webSearchProvider) { _ in syncCoordinator.syncAll() }
        .onChange(of: providerKeys.braveSearchApiKey) { _ in syncCoordinator.syncAll() }
        .onChange(of: providerKeys.tavilyApiKey) { _ in syncCoordinator.syncAll() }
        .onChange(of: providerKeys.serperApiKey) { _ in syncCoordinator.syncAll() }
    }
}

// MARK: - Provider Groups

private extension APIKeysSettingsSection {
    var openaiGroup: some View {
        GroupBox("OpenAI") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SecureField("sk-...", text: $providerKeys.openaiApiKey).textFieldStyle(.roundedBorder)
                    settingsStatusBadge(
                        connected: !providerKeys.openaiApiKey.isEmpty,
                        label: providerKeys.openaiApiKey.isEmpty ? "Not configured" : "Configured"
                    )
                }
            }.padding(4)
        }
    }

    var anthropicGroup: some View {
        GroupBox("Anthropic") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SecureField("sk-ant-...", text: $providerKeys.anthropicApiKey).textFieldStyle(.roundedBorder)
                    settingsStatusBadge(
                        connected: !providerKeys.anthropicApiKey.isEmpty,
                        label: providerKeys.anthropicApiKey.isEmpty ? "Not configured" : "Configured"
                    )
                }
                HStack {
                    settingsFieldLabel("Admin key (usage online)")
                    SecureField("sk-ant-admin-...", text: $providerKeys.anthropicAdminApiKey).textFieldStyle(.roundedBorder)
                    settingsStatusBadge(
                        connected: !providerKeys.anthropicAdminApiKey.isEmpty,
                        label: providerKeys.anthropicAdminApiKey.isEmpty ? "Optional" : "Configured"
                    )
                }
                settingsHintBox("Used only to fetch online Claude usage via Anthropic Admin API. Fallback remains local session usage.")
            }.padding(4)
        }
    }

    var geminiGroup: some View {
        GroupBox("Google Gemini") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SecureField("AIza...", text: $providerKeys.googleApiKey).textFieldStyle(.roundedBorder)
                    settingsStatusBadge(
                        connected: !providerKeys.googleApiKey.isEmpty,
                        label: providerKeys.googleApiKey.isEmpty ? "Not configured" : "Configured"
                    )
                }
            }.padding(4)
        }
    }

    var minimaxGroup: some View {
        GroupBox("MiniMax") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SecureField("API Key", text: $providerKeys.minimaxApiKey).textFieldStyle(.roundedBorder)
                    settingsStatusBadge(
                        connected: !providerKeys.minimaxApiKey.isEmpty,
                        label: providerKeys.minimaxApiKey.isEmpty ? "Not configured" : "Configured"
                    )
                }
            }.padding(4)
        }
    }

    var openRouterGroup: some View {
        GroupBox("OpenRouter") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SecureField("sk-or-...", text: $providerKeys.openrouterApiKey).textFieldStyle(.roundedBorder)
                    settingsStatusBadge(
                        connected: !providerKeys.openrouterApiKey.isEmpty,
                        label: providerKeys.openrouterApiKey.isEmpty ? "Not configured" : "Configured"
                    )
                }
                settingsHintBox("OpenRouter lets you use models from different providers with a single API key. Models are selected in chat.")
            }.padding(4)
        }
    }

    var grokGroup: some View {
        GroupBox("Grok (xAI)") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SecureField("xai-...", text: $providerKeys.grokApiKey).textFieldStyle(.roundedBorder)
                    settingsStatusBadge(
                        connected: !providerKeys.grokApiKey.isEmpty,
                        label: providerKeys.grokApiKey.isEmpty ? "Not configured" : "Configured"
                    )
                }
            }.padding(4)
        }
    }

    var webSearchGroup: some View {
        GroupBox("Web Search") {
            VStack(alignment: .leading, spacing: 10) {
                settingsFieldLabel("Search provider")
                Picker("", selection: $providerKeys.webSearchProvider) {
                    Text("DuckDuckGo (Free)").tag("duckduckgo")
                    Text("Brave Search").tag("brave")
                    Text("Tavily").tag("tavily")
                    Text("Serper (Google)").tag("serper")
                }
                .labelsHidden()
                .pickerStyle(.segmented)

                if providerKeys.webSearchProvider == "brave" {
                    HStack {
                        SecureField("BSA...", text: $providerKeys.braveSearchApiKey).textFieldStyle(.roundedBorder)
                        settingsStatusBadge(
                            connected: !providerKeys.braveSearchApiKey.isEmpty,
                            label: providerKeys.braveSearchApiKey.isEmpty ? "Key required" : "Configured"
                        )
                    }
                    settingsHintBox("Free tier: 2,000 queries/month. Get a key at brave.com/search/api")
                } else if providerKeys.webSearchProvider == "tavily" {
                    HStack {
                        SecureField("tvly-...", text: $providerKeys.tavilyApiKey).textFieldStyle(.roundedBorder)
                        settingsStatusBadge(
                            connected: !providerKeys.tavilyApiKey.isEmpty,
                            label: providerKeys.tavilyApiKey.isEmpty ? "Key required" : "Configured"
                        )
                    }
                    settingsHintBox("Free tier: 1,000 queries/month. AI-optimized search. Get a key at tavily.com")
                } else if providerKeys.webSearchProvider == "serper" {
                    HStack {
                        SecureField("API Key", text: $providerKeys.serperApiKey).textFieldStyle(.roundedBorder)
                        settingsStatusBadge(
                            connected: !providerKeys.serperApiKey.isEmpty,
                            label: providerKeys.serperApiKey.isEmpty ? "Key required" : "Configured"
                        )
                    }
                    settingsHintBox("Free tier: 2,500 queries/month. Google Search results. Get a key at serper.dev")
                } else {
                    settingsHintBox("DuckDuckGo is free and requires no API key. Results are extracted via HTML scraping.")
                }
            }.padding(4)
        }
    }
}
