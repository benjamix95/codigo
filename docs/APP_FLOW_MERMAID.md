# App flow ufficiale (v2, codice reale + guardie)

## 1) Mappa macro dei flussi principali

- Bootstrap & readiness: `AppLaunched -> AppDelegateBoot -> StoresHydrated -> MainUIReady`
- Contesto e navigazione: `Workspace/Project loaded -> Conversation selected -> Panel selection`
- Chat + provider: `sendMessage -> ProviderGuard -> Streaming -> Tool/Text response -> ResponseCommitted`
- Modalità operative: `Mode decision -> Plan/Swarm/Debug` con transizioni dedicate
- Git: `GitPanel open -> Refresh -> Action -> Refresh/Error`
- Persistenza: `StatePersistRequest -> StatePersisted -> StateRestored / StateRecoveryFallback`

## 2) Diagramma livello 1 (macro flow)

```mermaid
flowchart TD
    A["AppLaunched @main\nCodigoApp"] --> B["applicationDidFinishLaunching"]
    B --> C["Window lifecycle ready"]
    C --> D["ProvidersRegistration\nProviderRegistry + account router"]
    C --> E["MCP/Update preflight (best effort)"]
    D --> F["StoresHydrated\nWorkspaceStore, ProjectContextStore, ChatStore..."]
    F --> G["MainUIReady\nContentView + NavigationSplitView"]
    G --> H["SidebarReady"]
    H --> I{"Context valid?"}
    I -->|No| J["StateRecoveryFallback"]
    I -->|Sì| K["ProjectLoaded"]
    K --> L["ConversationSelected"]
    L --> M["Panel selection"]
    M --> N["ChatPanelActive"]
    M --> O["GitPanelActive"]
    M --> P["SecondaryPanelsAvailable"]
    P --> Q["PlanPanel / SwarmPanel / DebugPanel / ReviewPanel"]
    N --> R["ChatInputReceived"]
    R --> S["ProviderGuard"]
    S -->|No| T["ProviderAuthRequired"]
    S -->|Sì| U["StreamingStarted"]
    T --> V["AuthInProgress"]
    V --> U
    U --> W["StreamingRunning"]
    W --> X{"Tool? / Plain text?"}
    X -->|Tool| Y["ToolInvocation"]
    X -->|Plain text| Z["TextResponseCommit"]
    Y --> AA["EventNormalizer"]
    AA --> AB["ResponseCommitted"]
    Z --> AB
    AB --> AC["TaskActivity + ToolTrace log"]
    W --> AD["StreamingError"]
    AD --> N
    O --> AE["GitPanelRefresh"]
    AE --> AF["GitStatusLoaded"]
    AF --> AG["GitActionRunning"]
    AG -->|"ok"| AH["GitActionSuccess + refresh"]
    AG -->|"err"| AI["GitError"]
    L --> AM["Mode decision"]
    AM -->|plan| AN["PlanFlowStarted"]
    AM -->|swarm| AO["SwarmStarted"]
    AM -->|debug| AP["DebugSessionStarted"]
    AN --> AQ{"Clarification required?"}
    AQ -->|Sì| AR["PlanAwaitingClarification"]
    AQ -->|No| AS["PlanProposalReady"]
    AR --> AN
    AS --> AT["PlanFlowResolved"]
    AT --> AC
    G --> AU["StatePersistRequest"]
    AU --> AV["StatePersisted"]
    AV --> AW["StateRestored"]
    AV --> AX["StateRecoveryFallback"]
    AW --> G
    AX --> G
```

## 3) Diagramma livello 2 (dettaglio sottosistemi critici)

```mermaid
flowchart TD
    subgraph "A. Bootstrap e inizializzazione"
        A0["AppLaunched"] --> A1["AppDelegateBoot"]
        A1 --> A2["WindowLifecycleReady"]
        A2 --> A3["ProvidersRegistered"]
        A2 --> A4["MCP/Update preflight"]
        A3 --> A5["StoresHydrated"]
        A5 --> A6["MainUIReady"]
    end

    subgraph "B. Navigazione contesto"
        A6 --> B1["SidebarReady"]
        B1 --> B2{"contextId valido?"}
        B2 -->|No| B3["StateRecoveryFallback"]
        B2 -->|Sì| B4["ProjectContextLoaded"]
        B4 --> B5["ConversationSelected"]
        B5 --> B6{"Panel active?"}
        B6 -->|chat| B7["ChatPanelActive"]
        B6 -->|git| B8["GitPanelActive"]
        B6 -->|secondary| B9["Plan/Swarm/Debug/Review Panel"]
    end

    subgraph "C. Chat + provider"
        B7 --> C1["sendMessage"]
        C1 --> C2{"providerReady?"}
        C2 -->|No| C3["ProviderAuthRequired"]
        C2 -->|Sì| C4["startStreaming"]
        C3 --> C5["AuthInProgress"]
        C5 --> C4
        C4 --> C6{"Tool invoked?"}
        C6 -->|Sì| C7["ToolInvocation"]
        C6 -->|No| C8["PlainTextResponse"]
        C7 --> C9["EventNormalizer"]
        C8 --> C10["ResponseCommitted"]
        C9 --> C10
        C10 --> C11["ChatStore + TaskActivity"]
        C4 --> C12["StreamingError"]
        C12 --> B7
    end

    subgraph "D. Mode operative"
        B7 --> D1{"Mode decision"}
        D1 -->|plan| D2["PlanFlowStarted"]
        D1 -->|swarm| D3["SwarmStarted"]
        D1 -->|debug| D4["DebugSessionStarted"]
        D2 --> D5{"Need clarification?"}
        D5 -->|Sì| D6["PlanAwaitingClarification"]
        D5 -->|No| D7["PlanProposalReady"]
        D6 --> D2
        D7 --> D8["PlanFlowResolved"]
        D8 -->|Fail| D9["PlanFlowFailed"]
    end

    subgraph "E. Git"
        B8 --> E1["refresh()"]
        E1 --> E2["GitStatusLoaded"]
        E2 --> E3{"action?"}
        E3 -->|commit/pull/push/stage| E4["GitActionRunning"]
        E4 --> E5["GitActionSuccess"]
        E4 --> E6["GitError"]
        E5 --> E2
    end

    subgraph "F. Persistenza"
        B5 --> F1["StatePersistRequest"]
        B8 --> F1
        C11 --> F1
        F1 --> F2["StatePersisted"]
        F2 --> F3["StateRestored"]
        F3 --> A6
    end
```

## 4) Flusso → Moduli → output (matrice)

| Flusso | Moduli principali | Trigger | Stato/Output osservabile |
| --- | --- | --- | --- |
| Bootstrap | `CoderIDEApp`, `AppDelegate`, provider registry | Avvio app | `AppLaunched`, `ProvidersRegistered`, `StoresHydrated`, `MainUIReady` |
| Contesto | `ContentView`, `SidebarView`, `WorkspaceStore`, `ProjectContextStore` | cambio workspace/thread | `ProjectLoaded`, `ConversationSelected`, `Panel selection` |
| Chat/LLM | `ChatPanelView`, `ConversationFlowCoordinator`, `EventNormalizer`, `ChatStore` | invio messaggio | `MessageQueued`, `StreamingRunning`, `ToolInvocation`, `ResponseCommitted` |
| Provider auth | `CLIAccountRouter`, `CLIMultiAccountProviderAdapter`, `CLIAccountLoginCoordinator`, `ProfileSwitcher` | send con provider non autenticato | `ProviderAuthRequired`, `AuthInProgress`, `ProviderAuthenticated`, `AuthError` |
| Plan/swarm/debug | `ModeControlsBarView`, `PlanPanelView`, `SwarmPanel`, `DebugPanelView` | cambio mode | `ModeSelected`, `PlanFlowStarted`, `PlanFlowResolved/Failed`, `SwarmStarted`, `DebugSessionStarted` |
| Git | `GitPanelView`, `GitPanelStore`, `GitService` | open/git action | `GitStatusLoaded`, `GitActionRunning`, `GitActionSuccess`, `GitError` |
| Persistenza | `WorkspaceStore`, `ProjectContextStore`, defaults/local state | chiusura/switch | `StatePersisted`, `StateRestored`, `StateRecoveryFallback` |

## 5) Out of scope

- Micro-UI dei singoli componenti non proprietari.
- Implementazioni interne di librerie esterne (SDK LLM, runtime shell/git/MCP non proprietario).
- Dettagli di toolchain CI/build pipeline non parte del flusso runtime utente.

## 6) Nota per integrazione successiva

- I nodi con fallback sono mantenuti espliciti per migliorare troubleshooting e onboarding.
- Le decision point (`providerReady?`, `contextId valido?`, `tool?`, `Mode`, `Git action?`) sono tratte dai flussi osservati in runtime.
