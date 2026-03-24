# God Views & UI Decomposition — 2026-03-24

## Problema

6 God Views con eccessivo accoppiamento, proprietà esplose nel body scope, e logica di rete/processo nel layer view.

## Interventi

### 1. ChatTurnView (739 → 223 righe)

**File estratti:**
- `ChatTurnTimelineOrdering.swift` — enum con filtro blocchi visibili, narrativi, dettaglio
- `ChatTurnTimelineInterleaver.swift` — enum con logica interleaving timeline + collapsing eventi tool consecutivi
- `InlineToolTraceViews.swift` — 3 struct view (InlineToolTraceEventView, InlineToolTraceGroupView, InlineToolTraceGroupRow)

**Cambio architetturale:** ForEach con 6 branch estratto in `segmentView(for:)` @ViewBuilder.

### 2. ContentView (54 property → UIPanelCoordinator)

**File creato:**
- `UIPanelCoordinator.swift` — ObservableObject con 22 @Published (panel visibility, navigation, folder picker)

**File aggiornati:** 7 extension files (~85 occorrenze) con prefix `panelCoordinator.` / `$panelCoordinator.`

**Risultato:** Le 7 @AppStorage di layout restano su ContentView. Lo state mutabile e' centralizzato.

### 3. SettingsView (76 @AppStorage → 9 sezioni standalone)

**Problema re-render risolto:** Ogni @AppStorage nel body scope invalidava l'intera view. Ora ogni sezione e' una View autonoma con i propri @AppStorage e onChange.

**Infrastruttura creata:**
- `SettingsContainers.swift` — 6 DynamicProperty structs (SettingsProviderKeys, SettingsCLIConfig, SettingsRuntimeConfig, SettingsBehaviorConfig, SettingsAppearanceConfig, SettingsIndexConfig)
- `SettingsSyncCoordinator.swift` — ObservableObject, legge da UserDefaults via `ProviderFactoryConfig.fromUserDefaults()`
- `CodexTomlSaver.swift` — logica salvataggio config.toml estratta
- `ProviderFactoryConfig.fromUserDefaults()` — factory statica su ProviderFactoryConfig

**Sezioni standalone create:**
| Sezione | File | Righe |
|---------|------|-------|
| APIKeysSettingsSection | APIKeysSettingsSection.swift | 182 |
| CLIToolsSettingsSection | CLIToolsSettingsSection.swift + 4 ext | 108+555 |
| BehaviorSettingsSection | SettingsView+Behavior.swift | ~169 |
| AppearanceSettingsSection | SettingsView+Appearance.swift | ~142 |
| CodebaseIndexSettingsSection | SettingsView+CodebaseIndex.swift | ~161 |
| CustomSettingsSection | CustomSettingsSection.swift | 191 |
| RulesSettingsSection | RulesSettingsSection.swift | 218 |

**SettingsView shell:** 90 righe, zero @AppStorage, zero onChange.

**File rimossi:** SettingsView+Sync.swift, SettingsView+Persistence.swift, SettingsView+Sections.swift, SettingsView+Custom.swift, SettingsView+CustomActions.swift, SettingsView+CodexCustomModel.swift, SettingsView+Accounts.swift

### 4. UsageFooterView (21 @State → 2 struct container)

**File creato:**
- `UsageFooterWorktreeState.swift` — `UsageFooterWorktreeState` (14 prop) + `UsageFooterContextState` (5 prop + static queue)

**File aggiornati:** 7 extension files (~110 occorrenze) con prefix `wt.` / `ctx.`

### 5. OpenRouterLoginView — Network → Service Layer

**File creato:**
- `OpenRouterAuthService.swift` — enum con `exchangeCodeForKey()`, `generateCodeVerifier()`, `generateCodeChallenge()`

**Risultato:** URLSession completamente rimosso dal layer view.

### 6. CodexLoginView — Process/Polling → Service Layer

**File creato:**
- `CodexLoginService.swift` — actor con `loginWithAPIKey()`, `runBrowserLogin()`, `pollForCompletion()`

**Risultato:** Process execution e polling completamente rimossi dal layer view.

## Test Creati

| File | Componente | Casi |
|------|-----------|------|
| ProviderFactoryConfigFromDefaultsTests | fromUserDefaults() | 5 |
| ChatTurnTimelineOrderingTests | Filtro blocchi | 5 |
| ChatTurnTimelineInterleaverTests | Interleaving segments | 7 |
| OpenRouterAuthServiceTests | PKCE verifier/challenge | 7 |
| UIPanelCoordinatorTests | Default state, toggle, modes | 5 |
| SettingsSyncCoordinatorTests | Bind, nil safety | 3 |
| CodexLoginServiceTests | Invalid path, enum cases | 4 |

## Metriche

- **File toccati:** ~40
- **Rename meccanici:** ~500+
- **Righe max per file:** tutte sotto 300
- **Re-render SettingsView:** da "ogni cambio invalida tutto" a "ogni sezione e' isola indipendente"
