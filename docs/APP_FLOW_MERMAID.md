# Flusso completo app (Mermaid)

```mermaid
flowchart TD
    A[Avvio app\nCodigoApp @main] --> B[Inizializzazione Store\nChat/Workspace/ProjectContext/OpenFiles\nTaskActivity/ToolTrace/Todo/Swarm/Git/Plan]
    B --> C[registerProviders()\nProviderFactory + ProviderRegistry]
    C --> C1[Provider LLM\nOpenAI API\nAnthropic API\nGoogle API\nOpenRouter API\nMiniMax API\nGrok API\nCodex CLI\nClaude CLI\nGemini CLI]
    B --> D[ContentView\nNavigationSplitView]

    D --> E[SidebarView\nthread + contesto progetto]
    D --> F[EditorPlaceholderView + TerminalPanelView\n(pannello IDE)]
    D --> G[ChatPanelView\n(composer + timeline + pannelli)]
    D --> H[GitPanelView]
    D --> I[SettingsView]

    E --> J[ProjectContextStore\nworkspace/single-project\nactive context]
    E --> K[WorkspaceStore\nworkspaces + active workspace]
    K --> K1[CodebaseIndex.indexWorkspace()]
    K1 --> K2[FileWatcher\naggiornamenti realtime indice]

    G --> L[Input utente\nChatComposerView]
    L --> M[ChatStore\nappend messaggio user\nset task active]
    M --> N{Modalita` conversazione}

    N -->|Agent| O[ProviderRegistry.selectedProvider]
    N -->|Plan| P[Plan flow\nAnalyze -> Questions -> Options -> Build]
    N -->|Agent Swarm| Q[SwarmOrchestrator\nplanner/coder/debugger/reviewer/testWriter]
    N -->|Code Review| R[CodeReviewMultiSwarmProvider\npartition + review loops]

    P --> O
    Q --> O
    R --> O

    O --> S[LLMProvider.generateResponseStream]
    S --> T{Tool Runtime abilitato?}

    T -->|Si`| U[ToolEnabledLLMProvider]
    U --> V[UnifiedToolRuntime.execute]
    T -->|No| W[Output testuale provider]

    V --> V1[Tool locali\nread/read_range/list_dir/glob/grep\nstr_replace/write/create_file\nrun_tests/build_project/diagnostics\ngit_diff/bash]
    V --> V2[Tool indicizzati\nsemantic_search/codebase_search\nfind_symbol/find_references]
    V --> V3[Web tools\nweb_search/web_fetch]
    V --> V4[MCP tools\nmcp_list_servers/mcp_list_tools\nmcp_describe_tool/mcp_call]

    V4 --> V5[MCPSessionManager\nMCPTransportFactory\nMCPServerConfig]

    V1 --> X[Event stream normalizzato\nProviderToolEventMapper + EventNormalizer]
    V2 --> X
    V3 --> X
    V4 --> X
    W --> X

    X --> Y[ChatStore\nappend/update messaggi assistant\nstreaming + markers]
    X --> Z[Store secondari\nToolTraceStore\nTaskActivityStore\nTodoStore\nSwarmProgressStore\nDebugStore\nChangedFilesStore]

    Y --> G
    Z --> G

    M --> AA[Persistenza locale\nUserDefaults\nconversazioni/plan board/workspaces/settings]
    J --> AA
    K --> AA
    Z --> AA

    G --> AB[UI secondarie\nPlanPanelView\nDebugPanelView\nSwarmPanelView\nCodeReviewPanelView]
    AB --> Y

    A --> AC[MenuBarExtra\nUsageMenuBarView]
    AC --> AD[ProviderUsageStore + AccountUsageDashboardStore]
```
