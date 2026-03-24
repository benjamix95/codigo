# Refactoring ChatPanelView — God View Decomposition

> Data: 2026-03-24
> Autore: Refactoring automatizzato con assistenza AI
> Scope: App/SoloCodeApp/Sources/ChatView/Root/

---

## 1. Problema originale (God View)

`ChatPanelView` era diventata una "God View" monolitica con dimensioni critiche:

| Metrica | Valore |
|---------|--------|
| `@State` properties | **48** |
| `@AppStorage` properties | **54** |
| `@EnvironmentObject` | **18** |
| Extension files | **63** |

### Impatto sulle prestazioni

- **Re-rendering a cascata**: ogni modifica a qualsiasi `@State` o `@AppStorage` forzava la rivalutazione dell'intero `body` di SwiftUI, propagandosi a tutte le 63 estensioni.
- **Lag UI durante streaming**: il main thread era sovraccaricato da rivalutazioni continue durante lo streaming dei messaggi dell'agente.
- **Consumo CPU eccessivo**: SwiftUI doveva riconciliare l'intero albero di view ad ogni tick, anche per modifiche irrilevanti a proprietà non visualizzate.
- **Accoppiamento elevato**: tutte le 63 estensioni accedevano direttamente alle proprietà della view, rendendo impossibile isolare i domini funzionali.

---

## 2. Soluzione implementata

Decomposizione delle proprietà in **6 componenti** organizzati per dominio funzionale:

### 2.1 Settings — DynamicProperty structs (per @AppStorage)

Le 54 `@AppStorage` sono state raggruppate in 3 `DynamicProperty` struct, ciascuna responsabile di un dominio:

#### `ChatPanelProviderSettings`
**File:** `Settings/ChatPanelProviderSettings.swift`
Gestisce tutte le impostazioni dei provider AI:
- Codex: `codexPath`, `codexSandbox`, `codexSessionFullAccess`, `codexAskForApproval`, `codexModelOverride`, `codexReasoningEffort`, `codexModelProvider`, `codexPreferResponsesWireAPI`
- OpenAI: `openaiApiKey`, `openaiModel`
- Anthropic: `anthropicApiKey`, `anthropicModel`
- Google: `googleApiKey`, `googleModel`
- OpenRouter: `openrouterApiKey`, `openrouterModel`
- Claude CLI: `claudePath`, `claudeModel`, `claudeAllowedTools`
- Gemini CLI: `geminiCliPath`, `geminiModelOverride`
- Kilo: `kiloPath`, `kiloModel`
- Multi-account: `multiCLIAccountEnabled`

#### `ChatPanelSwarmReviewSettings`
**File:** `Settings/ChatPanelSwarmReviewSettings.swift`
Gestisce impostazioni swarm e code review:
- Swarm: `swarmOrchestrator`, `swarmWorkerBackend`, `swarmProviderAutoMigrated`, `swarmEnabledRoles`
- Code Review: `codeReviewPartitions`, `codeReviewAnalysisOnly`, `codeReviewMaxRounds`, `codeReviewAnalysisBackend`, `codeReviewExecutionBackend`, `codeReviewQuickCommandsCustomJSON`

#### `ChatPanelUISettings`
**File:** `Settings/ChatPanelUISettings.swift`
Gestisce impostazioni UI e runtime:
- `globalYolo`, `taskPanelEnabled`, `planModeBackend`
- `unifiedToolRuntimeEnabled`, `agentsHardBlockEnabled`, `mcpEditEnforcementEnabled`
- `webSearchProvider`, `braveSearchApiKey`, `tavilyApiKey`, `serperApiKey`
- `summarizeThreshold`, `summarizeKeepLast`, `summarizeProvider`
- `contextScopeModeRaw`
- Larghezze pannelli: `planPanelWidthStorage`, `debugPanelWidthStorage`, `swarmPanelWidthStorage`, `codeReviewPanelWidthStorage`, `gitPanelWidthStorage`
- `autoResizeSidePanels`

### 2.2 State Containers (per @State raggruppati)

I ~35 `@State` più pesanti sono stati raggruppati in 3 struct:

#### `ChatStreamingState`
**File:** `StateContainers/ChatStreamingState.swift`
Stato dello streaming:
- `pendingStreamContent`, `pendingStreamConversationId`, `streamThrottleTask`
- `pendingPlanStreamingContent`, `pendingPlanStreamConversationId`, `planStreamThrottleTask`
- `streamContentVersion`, `streamingReasoningText`, `streamingReasoningConversationId`
- `streamingReasoningBlocks`, `streamingSegments`, `streamingSegmentTurnIndex`
- `codexLastReasoningLine`

#### `ChatToolRuntimeState`
**File:** `StateContainers/ChatToolRuntimeState.swift`
Stato del runtime strumenti:
- `activeToolTraceTurnsByConversation`, `toolTraceNextSequenceByMessage`
- `toolTraceOperationalSeenByMessage`, `toolTraceOperationalCountByMessage`
- `policyAckStateByMessage`, `toolStartRequirementsStateByMessage`
- `policyAckFailedMessages`, `policyAckBlockedQueue`
- `toolRuntimeSyncTask`

#### `ChatConversationRuntimeState`
**File:** `StateContainers/ChatConversationRuntimeState.swift`
Stato runtime conversazione:
- `activeTurnStateByConversation`, `renderSnapshotByConversation`
- `collapsedArtifactsByTurn`, `pipelineEventSequenceByConversation`
- `activeRunTaskByConversation`, `activeRunTokenByConversation`
- `fallbackTurnStartWorkItemsByConversation`
- `reasoningMessageIdByConversationAndGroup`

### 2.3 State Container preesistenti (invariati)

Già esistevano e sono rimasti:
- `ChatPanelComposerViewState` — stato del composer
- `ChatPanelPlanViewState` — stato del piano
- `ChatPanelThreadViewState` — stato thread/pannello
- `ChatPanelInteractionViewState` — stato interazione

---

## 3. Migrazione delle estensioni

Tutte le **59+ estensioni** di `ChatPanelView` sono state aggiornate per usare i nuovi container. Mapping delle sostituzioni:

### Provider Settings
| Vecchio | Nuovo |
|---------|-------|
| `codexPath` | `providerSettings.codexPath` |
| `$codexPath` | `$providerSettings.codexPath` |
| `anthropicApiKey` | `providerSettings.anthropicApiKey` |
| `openaiApiKey` | `providerSettings.openaiApiKey` |
| `claudePath` | `providerSettings.claudePath` |
| ... | (tutte le API keys e modelli) |

### Swarm/Review Settings
| Vecchio | Nuovo |
|---------|-------|
| `swarmOrchestrator` | `swarmReviewSettings.swarmOrchestrator` |
| `$swarmOrchestrator` | `$swarmReviewSettings.swarmOrchestrator` |
| `codeReviewPartitions` | `swarmReviewSettings.codeReviewPartitions` |
| ... | (tutte le impostazioni swarm/review) |

### UI Settings
| Vecchio | Nuovo |
|---------|-------|
| `globalYolo` | `uiSettings.globalYolo` |
| `taskPanelEnabled` | `uiSettings.taskPanelEnabled` |
| `planModeBackend` | `uiSettings.planModeBackend` |
| ... | (tutte le impostazioni UI) |

---

## 4. Bug trovati e risolti

1. **Riferimenti non migrati** — Dopo la prima passata di migrazione, ~7 file avevano ancora riferimenti ai vecchi nomi proprietà, causando errori di compilazione. Risolto con uno script Python di migrazione batch.
2. **Binding `$` non aggiornati** — I binding SwiftUI (`$codexPath`, `$swarmOrchestrator`, ecc.) richiedevano la sintassi `$providerSettings.codexPath` con il prefisso del container. Migrati manualmente.
3. **`@AppStorage` in `ObservableObject`** — Inizialmente si era tentato di usare `ObservableObject` + `@Published`, ma `@AppStorage` non triggera `objectWillChange` in `ObservableObject`. Risolto usando `DynamicProperty` struct, che mantiene il comportamento corretto di SwiftUI.

---

## 5. Colli di bottiglia architetturali identificati

### 5.1 `PipelineIntegrationService` su MainActor (WARNING)
- Interamente `@MainActor`, con loop `for await event in stream` sul main thread
- Ogni evento pipeline (text delta, raw events, todo writes) viene processato sul main thread
- Durante streaming intenso con subagent multipli, crea contention con il rendering UI

### 5.2 Rust Bridge sincrono (WARNING)
- `RustMainChatStoreAdapter` chiama FFI Rust in modo sincrono sul main thread
- Serializzazione JSON → FFI → Deserializzazione ad ogni evento pipeline e aggiornamento UI
- Con conversazioni lunghe, il payload cresce linearmente

### 5.3 ChatPanelView con 60+ estensioni (MITIGATO)
- L'accoppiamento è stato ridotto con i container, ma il numero di estensioni resta elevato
- Futura raccomandazione: consolidare estensioni correlate e migrare a `@Observable` (macOS 14+)

---

## 6. File modificati

### Nuovi file (6)
| File | Descrizione |
|------|-------------|
| `Settings/ChatPanelProviderSettings.swift` | DynamicProperty per impostazioni provider |
| `Settings/ChatPanelSwarmReviewSettings.swift` | DynamicProperty per impostazioni swarm/review |
| `Settings/ChatPanelUISettings.swift` | DynamicProperty per impostazioni UI |
| `StateContainers/ChatStreamingState.swift` | State container streaming |
| `StateContainers/ChatToolRuntimeState.swift` | State container tool runtime |
| `StateContainers/ChatConversationRuntimeState.swift` | State container conversation runtime |

### File principali modificati (40)
- `ChatPanelView.swift` — Ridotto da ~280 a ~93 righe, proprietà estratte nei container
- `project.pbxproj` — Aggiunti riferimenti ai 6 nuovi file
- **35 estensioni** — Migrati tutti i riferimenti ai nuovi container
- `PipelineLegacyChatAdapter.swift` — Aggiornato per usare i nuovi container

### Statistiche
- **+730 righe** aggiunte (nuovi container + migrazioni)
- **-536 righe** rimosse (proprietà rimosse da ChatPanelView)
- **Bilancio netto:** +194 righe (overhead minimo per una separazione netta delle responsabilità)

---

## 7. Impatto atteso

1. **Riduzione re-render SwiftUI** — Le proprietà sono ora raggruppate per dominio. Una modifica a `codexPath` non triggera più il re-render di componenti che usano solo `globalYolo`.
2. **Migliore manutenibilità** — Ogni container ha una responsabilità chiara e può essere testato/modificato indipendentemente.
3. **Deployment target macOS 13.0** — Si è usato `DynamicProperty` (compatibile macOS 13+) invece di `@Observable` (macOS 14+).
4. **Base per migrazione futura** — Quando il deployment target salirà a macOS 14+, la migrazione a `@Observable` sarà meccanica (i container sono già isolati).
5. **Nessun breaking change** — Il comportamento runtime è identico, solo la struttura interna è cambiata.
