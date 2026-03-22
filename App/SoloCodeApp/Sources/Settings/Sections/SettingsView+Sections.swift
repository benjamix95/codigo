import SwiftUI
import CoderEngine

extension SettingsView {
    @ViewBuilder
    var detailContent: some View {
        switch selectedSection {
        case .custom:
            customSection
        case .apiKeys:
            apiKeysSection
        case .cliTools:
            cliToolsSection
        case .mcp:
            mcpSection
        case .skillsPlugins:
            SkillsPluginsSection()
        case .rules:
            rulesSection
        case .codebaseIndex:
            codebaseIndexSection
        case .behavior:
            behaviorSection
        case .appearance:
            appearanceSection
        }
    }
    var apiKeysSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader(title: "API Keys", subtitle: "API keys for AI providers", icon: "key.fill")

            GroupBox("OpenAI") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        SecureField("sk-...", text: $openaiApiKey).textFieldStyle(.roundedBorder)
                        statusBadge(connected: !openaiApiKey.isEmpty, label: openaiApiKey.isEmpty ? "Not configured" : "Configured")
                    }
                }.padding(4)
            }

            GroupBox("Anthropic") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        SecureField("sk-ant-...", text: $anthropicApiKey).textFieldStyle(.roundedBorder)
                        statusBadge(connected: !anthropicApiKey.isEmpty, label: anthropicApiKey.isEmpty ? "Not configured" : "Configured")
                    }
                    HStack {
                        fieldLabel("Admin key (usage online)")
                        SecureField("sk-ant-admin-...", text: $anthropicAdminApiKey).textFieldStyle(.roundedBorder)
                        statusBadge(
                            connected: !anthropicAdminApiKey.isEmpty,
                            label: anthropicAdminApiKey.isEmpty ? "Optional" : "Configured"
                        )
                    }
                    hintBox("Used only to fetch online Claude usage via Anthropic Admin API. Fallback remains local session usage.")
                }.padding(4)
            }

            GroupBox("Google Gemini") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        SecureField("AIza...", text: $googleApiKey).textFieldStyle(.roundedBorder)
                        statusBadge(connected: !googleApiKey.isEmpty, label: googleApiKey.isEmpty ? "Not configured" : "Configured")
                    }
                }.padding(4)
            }

            GroupBox("MiniMax") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        SecureField("API Key", text: $minimaxApiKey).textFieldStyle(.roundedBorder)
                        statusBadge(connected: !minimaxApiKey.isEmpty, label: minimaxApiKey.isEmpty ? "Not configured" : "Configured")
                    }
                }.padding(4)
            }

            GroupBox("OpenRouter") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        SecureField("sk-or-...", text: $openrouterApiKey).textFieldStyle(.roundedBorder)
                        statusBadge(connected: !openrouterApiKey.isEmpty, label: openrouterApiKey.isEmpty ? "Not configured" : "Configured")
                    }
                    hintBox("OpenRouter lets you use models from different providers with a single API key. Models are selected in chat.")
                }.padding(4)
            }

            GroupBox("Grok (xAI)") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        SecureField("xai-...", text: $grokApiKey).textFieldStyle(.roundedBorder)
                        statusBadge(connected: !grokApiKey.isEmpty, label: grokApiKey.isEmpty ? "Not configured" : "Configured")
                    }
                }.padding(4)
            }

            GroupBox("Web Search") {
                VStack(alignment: .leading, spacing: 10) {
                    fieldLabel("Search provider")
                    Picker("", selection: $webSearchProvider) {
                        Text("DuckDuckGo (Free)").tag("duckduckgo")
                        Text("Brave Search").tag("brave")
                        Text("Tavily").tag("tavily")
                        Text("Serper (Google)").tag("serper")
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)

                    if webSearchProvider == "brave" {
                        HStack {
                            SecureField("BSA...", text: $braveSearchApiKey).textFieldStyle(.roundedBorder)
                            statusBadge(connected: !braveSearchApiKey.isEmpty, label: braveSearchApiKey.isEmpty ? "Key required" : "Configured")
                        }
                        hintBox("Free tier: 2,000 queries/month. Get a key at brave.com/search/api")
                    } else if webSearchProvider == "tavily" {
                        HStack {
                            SecureField("tvly-...", text: $tavilyApiKey).textFieldStyle(.roundedBorder)
                            statusBadge(connected: !tavilyApiKey.isEmpty, label: tavilyApiKey.isEmpty ? "Key required" : "Configured")
                        }
                        hintBox("Free tier: 1,000 queries/month. AI-optimized search. Get a key at tavily.com")
                    } else if webSearchProvider == "serper" {
                        HStack {
                            SecureField("API Key", text: $serperApiKey).textFieldStyle(.roundedBorder)
                            statusBadge(connected: !serperApiKey.isEmpty, label: serperApiKey.isEmpty ? "Key required" : "Configured")
                        }
                        hintBox("Free tier: 2,500 queries/month. Google Search results. Get a key at serper.dev")
                    } else {
                        hintBox("DuckDuckGo is free and requires no API key. Results are extracted via HTML scraping.")
                    }
                }.padding(4)
            }

            hintBox("Models are selected directly from the chat bar, not from settings.")
        }
    }
    var cliToolsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader(title: "CLI Tools", subtitle: "Codex, Claude Code, and Gemini CLI", icon: "terminal")

            GroupBox("Codex CLI") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        fieldLabel("Path")
                        TextField("Auto-detect", text: $codexPath).textFieldStyle(.roundedBorder)
                        statusBadge(
                            connected: codexState.status.isLoggedIn,
                            label: codexState.status.isLoggedIn ? "Connected" : "Not connected"
                        )
                    }
                    Button("Connect to Codex") { connectToCodex() }
                        .buttonStyle(.borderedProminent).controlSize(.small)

                    HStack(spacing: 8) {
                        statusBadge(
                            connected: codexMCPHealth.isHealthy,
                            label: codexMCPHealth.statusLabel
                        )
                        Spacer()
                        Button("Re-check") {
                            codexMCPHealth.refresh()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        if codexMCPHealth.canRepair {
                            Button("Repair profiles") {
                                codexMCPHealth.repairProfiles()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }

                    Divider()
                    fieldLabel("Sandbox")
                    Picker("", selection: $codexSandbox) {
                        Text("Read Only").tag("read-only")
                        Text("Workspace Write").tag("workspace-write")
                        Text("Full Access").tag("danger-full-access")
                    }.labelsHidden().pickerStyle(.segmented)

                    fieldLabel("Approval")
                    Picker("", selection: $codexAskForApproval) {
                        Text("Never").tag("never")
                        Text("On request").tag("on-request")
                        Text("Untrusted").tag("untrusted")
                    }.labelsHidden().pickerStyle(.segmented)

                    fieldLabel("Speed")
                    Picker("", selection: $codexFastMode) {
                        Text("Standard").tag(false)
                        Text("Fast").tag(true)
                    }.labelsHidden().pickerStyle(.segmented)

                    Toggle("Prefer OpenAI Responses wire API", isOn: $codexPreferResponsesWireAPI)
                    hintBox(
                        "When enabled, Codex CLI runs with `model_providers.openai.wire_api=\"responses\"`."
                    )
                    hintBox("Fast mode controls Codex CLI inference speed across threads, subagents, and compaction.")

                    Toggle("Network access", isOn: $codexNetworkAccess)
                    Toggle("Check for updates", isOn: $codexCheckUpdate)
                }.padding(4)
            }

            codexCustomModelGroup

            multiAccountProviderSection(.codex)

            GroupBox("Claude Code") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        fieldLabel("Path")
                        TextField("Auto-detect", text: $claudePath).textFieldStyle(.roundedBorder)
                        let claudeDetected = ClaudeDetector.detect(
                            customPath: claudePath.isEmpty ? nil : claudePath
                        )
                        statusBadge(
                            connected: claudeDetected.isInstalled && claudeDetected.isLoggedIn,
                            label: !claudeDetected.isInstalled
                                ? "Not found"
                                : (claudeDetected.isLoggedIn ? "Connected" : "Token expired")
                        )
                    }

                    let claudeStatus = ClaudeDetector.detect(
                        customPath: claudePath.isEmpty ? nil : claudePath
                    )
                    if claudeStatus.isInstalled && !claudeStatus.isLoggedIn {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("OAuth token expired. Open Claude Desktop app to refresh, or click below.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Button("Re-authenticate Claude") {
                            connectToClaude()
                        }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                    }

                    Divider()
                    fieldLabel("Allowed tools")
                    let allTools = ["Read", "Edit", "Bash", "Write", "Search", "Task", "Glob", "Grep", "TodoRead", "TodoWrite"]
                    let selectedTools = parseClaudeAllowedTools()
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 6) {
                        ForEach(allTools, id: \.self) { tool in
                            let isOn = selectedTools.contains(tool)
                            Button {
                                var set = Set(selectedTools)
                                if isOn { set.remove(tool) } else { set.insert(tool) }
                                claudeAllowedTools = allTools.filter { set.contains($0) }.joined(separator: ",")
                            } label: {
                                Text(tool)
                                    .font(.system(size: 10, weight: isOn ? .semibold : .regular))
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(isOn ? Color.accentColor.opacity(0.15) : Color.clear, in: Capsule())
                                    .overlay(Capsule().strokeBorder(isOn ? Color.accentColor : Color.secondary.opacity(0.3)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }.padding(4)
            }

            multiAccountProviderSection(.claude)

            GroupBox("Gemini CLI") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        fieldLabel("Path")
                        TextField("Auto-detect", text: $geminiCliPath).textFieldStyle(.roundedBorder)
                        statusBadge(
                            connected: geminiState.status.isInstalled,
                            label: geminiState.status.isInstalled ? "Installed" : "Not found"
                        )
                    }
                    if !geminiState.status.isInstalled {
                        Button("Connect to Gemini") {
                            geminiState.refresh()
                            if geminiState.status.isInstalled { syncGemini() }
                        }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                    }
                }.padding(4)
            }
            .onAppear { geminiState.refresh() }

            multiAccountProviderSection(.gemini)

            GroupBox("Kilo CLI") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        fieldLabel("Path")
                        TextField("Auto-detect", text: $kiloPath).textFieldStyle(.roundedBorder)
                        statusBadge(
                            connected: kiloState.status.isInstalled,
                            label: kiloState.status.isInstalled ? "Installed" : "Not found"
                        )
                    }
                    if !kiloState.status.isInstalled {
                        Button("Detect Kilo") {
                            kiloState.refresh()
                            if kiloState.status.isInstalled { syncKilo() }
                        }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                    }
                    Divider()
                    fieldLabel("Model")
                    Picker("", selection: $kiloModel) {
                        Text("Auto").tag("")
                        ForEach(kiloModels, id: \.self) { m in
                            Text(m).tag(m)
                        }
                    }
                    .labelsHidden()
                }.padding(4)
            }
            .onAppear { kiloState.refresh() }
        }
        .sheet(item: $loginSheetAccount) { account in
            CLIAccountLoginSheet(
                account: account,
                providerPath: providerPath(for: account.provider),
                onDismiss: {
                    handleLoginSheetDismiss(for: account)
                }
            )
        }
    }
    var mcpSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader(title: "MCP Servers", subtitle: "Model Context Protocol — servers and tools", icon: "server.rack")
            MCPSettingsSection()
        }
    }
}
